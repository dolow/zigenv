const std = @import("std");
const testing = std.testing;

const zigenv = @import("./main.zig");

test "simple usage, .env file is loaded" {
    // Zigenv uses passed allocator to allocate internally kept .env definitions
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    // caller owns Zigenv value memory ownership
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{}).init(allocator);
    // free internally allocated memory
    defer env.deinit();
    // when .env has invalid format, error occurs
    try env.load();

    // undefined key become null
    const value = env.map.get("MY_VARIABLE");
    try testing.expect(std.mem.eql(u8, value.?, "should be loaded successfully"));
}

test "not existing stage" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{.stage = "notexist"}).init(allocator);
    defer env.deinit();
    const err = env.load();
    try testing.expectError(std.fs.File.OpenError.FileNotFound, err);
}

test "not default stage refers .env" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{}).init(allocator);
    defer env.deinit();
    try env.load();
    const stage = env.map.get("STAGE");
    try testing.expect(std.mem.eql(u8, stage.?, "default"));
}

test "undefined key become null" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{}).init(allocator);
    defer env.deinit();
    try env.load();
    const shoud_not_exists = env.map.get("NOT_EXISTS");
    try testing.expect(shoud_not_exists == null);
}

test "should load many keys" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{.stage = "case1"}).init(allocator);
    defer env.deinit();
    try env.load();

    try testing.expect(env.len == 11);

    var actual: ?[]const u8 = null;

    actual = env.map.get("TEST_1");
    try testing.expect(std.mem.eql(u8, actual.?, "1"));
    actual = env.map.get("TEST_2");
    try testing.expect(std.mem.eql(u8, actual.?, "2"));
    actual = env.map.get("TEST_3");
    try testing.expect(std.mem.eql(u8, actual.?, "3"));
    actual = env.map.get("TEST_4");
    try testing.expect(std.mem.eql(u8, actual.?, "4"));
    actual = env.map.get("TEST_5");
    try testing.expect(std.mem.eql(u8, actual.?, "5"));
    actual = env.map.get("TEST_6");
    try testing.expect(std.mem.eql(u8, actual.?, "6"));
    actual = env.map.get("TEST_7");
    try testing.expect(std.mem.eql(u8, actual.?, "7"));
    actual = env.map.get("TEST_8");
    try testing.expect(std.mem.eql(u8, actual.?, "8"));
    actual = env.map.get("TEST_9");
    try testing.expect(std.mem.eql(u8, actual.?, "9"));
}

// not run ?
test "should ignore empty lines and lines with space character(s)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{.stage = "case2"}).init(allocator);
    defer env.deinit();
    try env.load();

    try testing.expect(env.len == 4);

    var actual: ?[]const u8 = null;

    actual = env.map.get("TEST_1");
    try testing.expect(std.mem.eql(u8, actual.?, "value_after_blank_lines"));
    actual = env.map.get("TEST_2");
    try testing.expect(std.mem.eql(u8, actual.?, "value_before_trailing_blank_lines"));
}

test "should trim quotes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{.stage = "case3"}).init(allocator);
    defer env.deinit();
    try env.load();

    try testing.expect(env.len == 13);

    var actual: ?[]const u8 = null;

    actual = env.map.get("TEST_1");
    try testing.expect(std.mem.eql(u8, actual.?, "quoted"));
    actual = env.map.get("TEST_2");
    try testing.expect(std.mem.eql(u8, actual.?, "double quoted"));
    actual = env.map.get("TEST_3");
    try testing.expect(std.mem.eql(u8, actual.?, "single quote 'in' double quote"));
    actual = env.map.get("TEST_4");
    try testing.expect(std.mem.eql(u8, actual.?, "double quote \"in\" single quote"));
    actual = env.map.get("TEST_5");
    try testing.expect(std.mem.eql(u8, actual.?, "quated with trailing space"));
    actual = env.map.get("TEST_6");
    try testing.expect(std.mem.eql(u8, actual.?, "quated with trailing tab"));
    actual = env.map.get("TEST_7");
    try testing.expect(std.mem.eql(u8, actual.?, "quated with trailing spaces"));
    actual = env.map.get("TEST_8");
    try testing.expect(std.mem.eql(u8, actual.?, "quated with trailing tabs"));
    actual = env.map.get("TEST_9");
    try testing.expect(std.mem.eql(u8, actual.?, ""));
    actual = env.map.get("TEST_10");
    try testing.expect(std.mem.eql(u8, actual.?, "|&;()<>{}[]!"));
    // TODO: 
    actual = env.map.get("TEST_11");
    try testing.expect(std.mem.eql(u8, actual.?, "escaped\\\"quote"));
}

test "should handle multibyte characters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{.stage = "case4"}).init(allocator);
    defer env.deinit();
    try env.load();

    try testing.expect(env.len == 4);

    var actual: ?[]const u8 = null;

    actual = env.map.get("TEST_1");
    try testing.expect(std.mem.eql(u8, actual.?, "マルチバイト"));
    actual = env.map.get("TEST_2");
    try testing.expect(std.mem.eql(u8, actual.?, "mixture of マルチバイト and シングルバイト"));
}

// TODO: consider scenes zig used
test "should not convert escaped special character" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{.stage = "case5"}).init(allocator);
    defer env.deinit();
    try env.load();

    try testing.expect(env.len == 3);

    var actual: ?[]const u8 = null;

    actual = env.map.get("TEST_1");
    try testing.expect(std.mem.eql(u8, actual.?, "\\n"));
}

// TODO: length is as defined
test "should pick lately redefined variable" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{.stage = "case6"}).init(allocator);
    defer env.deinit();
    try env.load();

    try testing.expect(env.len == 4);

    var actual: ?[]const u8 = null;

    actual = env.map.get("TEST_1");
    try testing.expect(std.mem.eql(u8, actual.?, "2"));
}


test "should occur error when bared variable contains space" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env = zigenv.Zigenv(.{.stage = "invalid_case1"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.ValueFormatError.InvalidCharacter, err);
}


test "should occur error when value contains special characters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case2"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.ValueFormatError.InvalidCharacter, err);
}

test "should occur error when any line consists of no key value pairence" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case3"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.ParseError.UnpairedKeyValue, err);
}

test "should occur error when quoted value has space befor opening quote" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case4"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.ValueFormatError.InvalidCharacter, err);
}


test "should occur error when quoted value that does not close quote" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case5"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.ValueFormatError.UnpairedQuote, err);
}

test "should occur error when key consists of space" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case6"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.KeyFormatError.InvalidCharacter, err);
}

test "should occur error when key starts with space" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case7"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.KeyFormatError.InvalidCharacter, err);
}

test "should occur error when key starts with tab" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case8"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.KeyFormatError.InvalidCharacter, err);
}

test "should occur error when any blank line contains space" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case9"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.KeyFormatError.InvalidCharacter, err);
}

test "should occur error when any blank line contains tab" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case10"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.KeyFormatError.InvalidCharacter, err);
}


test "should occur error when quoted value does contain unescaped quote" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case11"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.ValueFormatError.UnescapedQuote, err);
}


test "should occur error when quoted value end with escaped quote" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    var env = zigenv.Zigenv(.{.stage = "invalid_case12"}).init(allocator);
    defer env.deinit();
    const err = env.load();

    try testing.expectError(zigenv.ValueFormatError.UnpairedQuote, err);
}
