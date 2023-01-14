# Zigenv

Zigenv is a typical `.env` loader for Zig.

It loads `.env` definiions on time.

# Fatures

- UTF-8 multibyte support
- quoted value support

# Usage

To load `.env`, write as following;

```zig
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
```

If there are multiple `.env` file like `.env.production`, set stage option to `zigenv.Config`.

```zig
var env = zigenv.Zigenv(.stage = "production").init(allocator);
```

# Test

```
zig test zigenv/main_test.zig
```

# License

MIT