const std = @import("std");
const testing = std.testing;

pub const ParseError = error {
    UnpairedKeyValue,
    UnpairedQuote,
};

pub const KeyFormatError = error {
    InvalidCharacter,
};

pub const ValueFormatError = error {
    InvalidCharacter,
    ContainSpaceCharacter,
    UnpairedQuote,
    UnescapedQuote,
};

const delimiter = '=';
const escape_sequence = '\\';

pub const Config = struct {
    base_name: []const u8 = ".env",
    stage: []const u8 = "",
    index_work_mem: usize = 8,
};

const MultibyteWidth = enum(u4) {
    One = 1,
    Two,
    Three,
    Four,
};

pub fn Zigenv(config: Config) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        map: std.StringHashMap([]const u8),
        buf: []u8,
        kv_indices: [][2]usize,
        len: usize,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .map = std.StringHashMap([]const u8).init(allocator),
                .buf = &[_]u8{},
                .kv_indices = &[_][2]usize{},
                .len = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();

            if (self.buf.len > 0) {
                self.allocator.free(self.buf);
            }
            if (self.kv_indices.len > 0) {
                self.allocator.free(self.kv_indices);
            }

            self.* = undefined;
        }

        pub fn get(self: *Self, key: []const u8) ?[]const u8 {
            for (self.kv_indices[0..self.len]) |_, i| {
                // search from the tail to pick redefinition first
                const kv_index = self.kv_indices[self.len - i - 1];
                const key_to = kv_index[1];
                if (std.mem.eql(u8, self.buf[kv_index[0]..key_to], key)) {
                    if (i == self.len - 1) {
                        return self.buf[key_to..self.buf.len];
                    }
                    const value_to = self.kv_indices[i+1][0];
                    return self.buf[key_to..value_to];
                }
            }

            return null;
        }

        pub fn load(self: *Self) !void {
            var file = try std.fs.cwd().openFile(self.get_env_file_name(), .{});
            defer file.close();

            var reader = std.io.bufferedReader(file.reader());
            var stream = reader.reader();

            var read_buf: [1024]u8 = undefined;
            while (try stream.readUntilDelimiterOrEof(&read_buf, '\n')) |line| {
                try self.parse_line(line);
            }

            for (self.kv_indices[0..self.len]) |kv_index, i| {
                var tail: usize = undefined;
                if (i == self.len - 1) {
                    tail = self.buf.len;
                } else {
                    tail = self.kv_indices[i + 1][0];
                }

                const key = self.buf[kv_index[0]..kv_index[1]];
                const value = self.buf[kv_index[1]..tail];
                
                try self.map.put(key, value);
            }
        }

        fn get_env_file_name(_: *Self) []const u8 {
            if (config.stage.len > 0) {
                return config.base_name ++ "." ++ config.stage;
            }
            
            return config.base_name;
        }

        fn parse_line(self: *Self, line: []u8) !void {
            // empty line
            if (line.len == 0) {
                return;
            }

            var parts = std.mem.split(u8, line, &[_]u8{delimiter});
            // return blank line
            const key: []const u8 = parts.next() orelse return;
            try validate_variable_name(key);

            var value_buf = std.ArrayList(u8).init(self.allocator);
            defer value_buf.deinit();

            if (parts.next()) |v| {
                try std.fmt.format(value_buf.writer(), "{s}", .{v});

                // in a case value contains delimiter(s)
                while (parts.next()) |chunk| {
                    try std.fmt.format(value_buf.writer(), "{c}{s}", .{delimiter, chunk});
                }
            } else {
                // no separator
                return ParseError.UnpairedKeyValue;
            }

            const value = try trim_quote(value_buf.items);
            if (value.len > 0) {
                // bared string must be validated
                if (value.len == value_buf.items.len) {
                    try validate_bared_value(value);
                } else {
                    try validate_quoted_value(value, value_buf.items[0]);
                }
            }

            const offset = self.buf.len;
            if (offset == offset + key.len) {
                return;
            }

            const stretch_size = offset + key.len + value.len;
            
            if (self.buf.len == 0) {
                var new_buf = try self.allocator.alloc(u8, stretch_size);
                self.buf = new_buf;
            } else {
                // NOTICE: return value of resize is changed to bool in master branch
                _ = self.allocator.resize(self.buf, stretch_size) orelse {
                    var new_buf = try self.allocator.alloc(u8, stretch_size);
                    std.mem.copy(u8, new_buf, self.buf);
                    self.allocator.free(self.buf);
                    self.buf = new_buf;
                };
            }

            self.buf.len = stretch_size;
            
            std.mem.copy(u8, self.buf[offset..(offset + key.len)], key);
            std.mem.copy(u8, self.buf[(offset + key.len)..(stretch_size)], value);

            var kv_stretch_size = self.kv_indices.len + config.index_work_mem;

            if (self.kv_indices.len == 0) {
                self.kv_indices = try self.allocator.alloc([2]usize, kv_stretch_size);
            } else if (self.len == self.kv_indices.len) {
                _ = self.allocator.resize(self.kv_indices, kv_stretch_size) orelse {
                    var new_kv_indices = try self.allocator.alloc([2]usize, kv_stretch_size);
                    std.mem.copy([2]usize, new_kv_indices, self.kv_indices);
                    self.allocator.free(self.kv_indices);
                    self.kv_indices = new_kv_indices;
                };
            } else {
                kv_stretch_size = self.kv_indices.len;
            }

            self.kv_indices.len = kv_stretch_size;

            self.kv_indices[self.len][0] = offset;
            self.kv_indices[self.len][1] = offset + key.len;
            
            self.len += 1;
        }
    };
}

fn trim_quote(value: []const u8) ![]const u8 {
    if (value.len == 0) {
        return value;
    }

    const first_char = value[0];

    if (first_char != '"' and first_char != '\'') {
        return value;
    }

    // trim trailing space characters
    for (value) |_, i| {
        const c = value[value.len - i - 1];
        // space characters
        if (c == 0x09 or c == 0x20) {
            continue;
        }
        if (c == first_char) {
            if (i == value.len - 1) {
                return ParseError.UnpairedQuote;
            }
            return value[1..value.len - i - 1];
        }
    }

    return ParseError.UnpairedQuote;
}

// UTF-8 table
// 0xxxxxxx                            0x00..0x7f             One    ASCII
// 110xxxxx 10xxxxxx                   0xc080..0xdfbf         Two    alphabet variants
// 1110xxxx 10xxxxxx 10xxxxxx          0xe08080..0xefbfbf     Three  other cultural griph
// 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx 0xf0808080..0xf7bfbfbf Four   emoji, etc
fn validate_bared_value(value: []const u8) !void {
    // set them to default at the end of the rune
    var width: MultibyteWidth = .One;
    var byte_index: usize = 0;

    // it's almost utf8 check but also invalidate general CLI special characters
    for (value) |c| {
        switch (c) {
            // invalid ASCII
            // unpaired bracket () is not supported currently
            0x00...0x20, '!', '"', '$', '&', '\'', '(', ')', ';', '<', '>', '`', '|', 0x7f => return ValueFormatError.InvalidCharacter,
            // valid ASCII
            '#', '%', '*', '+', ',', '-', '.', '/', 0x30...0x39, ':', '=', '?', '@',
            0x41...0x5a, '[', '\\', ']', '^', '_', 0x61...0x7a, '{', '}', '~' => {
                if (width != .One)  {
                    return ValueFormatError.InvalidCharacter;
                }
                byte_index = 0;
            },
            // multibyte rune range
            0x80...0xbf => {
                if (width == .One)  {
                    return ValueFormatError.InvalidCharacter;
                }
                byte_index += 1;

                // end of the rune
                if (byte_index == @enumToInt(width) - 1) {
                    width = .One;
                    byte_index = 0;
                }
            },
            // width token
            0xc0...0xdf => {
                if (width != .One)  {
                    return ValueFormatError.InvalidCharacter;
                }
                width = .Two;
            },
            0xe0...0xef => {
                if (width != .One)  {
                    return ValueFormatError.InvalidCharacter;
                }
                width = .Three;
            },
            0xf0...0xf7 => {
                if (width != .One)  {
                    return ValueFormatError.InvalidCharacter;
                }
                width = .Four;
            },
            // NOTE: or should pass through ?
            0xf8...0xff => unreachable,
        }
    }
}

fn validate_quoted_value(value: []const u8, quote_char: u8) !void {
    if (value[value.len - 1] == escape_sequence) {
        return ValueFormatError.UnpairedQuote;
    }
    var escape_token = false;
    for (value) |c| {
        if (c == escape_sequence) {
            escape_token = true;
        } else {
            if (c == quote_char and !escape_token) {
                return ValueFormatError.UnescapedQuote;
            }
            escape_token = false;
        }
    }
}

fn validate_variable_name(key: []const u8) !void {
    for (key) |c| {
        switch(c) {
            'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
            else => return KeyFormatError.InvalidCharacter,
        }
    }
}