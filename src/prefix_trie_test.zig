const std = @import("std");
const ArrayList = @import("std").ArrayList;
const Trie = @import("prefix_trie.zig").Trie;
const WordDataSpec = @import("prefix_trie.zig").WordDataSpec;
const serializeTrie = @import("prefix_trie.zig").serializeTrie;
const iterateSerializedTrie = @import("prefix_trie.zig").iterateSerializedTrie;

test "put and get" {
    const test_alloc = std.testing.allocator;
    var arena_alloc = std.heap.ArenaAllocator.init(test_alloc);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();
    var trie = Trie([]const u8).init();

    try trie.add(allocator, "foo", "v1");
    try trie.add(allocator, "foobar", "v2");
    try trie.add(allocator, "baz", "v3");

    try std.testing.expectEqual(@as(?[]const u8, "v1"), trie.get("foo"));
    try std.testing.expectEqual(@as(?[]const u8, "v2"), trie.get("foobar"));
    try std.testing.expectEqual(@as(?[]const u8, null), trie.get("foobars"));
}

test "put and iterate" {
    const test_alloc = std.testing.allocator;
    var arena_alloc = std.heap.ArenaAllocator.init(test_alloc);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();
    var trie = Trie([]const u8).init();
    try trie.add(allocator, "foo", "v1");
    try trie.add(allocator, "foobar", "v2");
    try trie.add(allocator, "baz", "v3");

    var keys = try ArrayList([]const u8).initCapacity(allocator, 4);
    var values = try ArrayList([]const u8).initCapacity(allocator, 4);
    var it = try trie.iterator(allocator);
    while (try it.next()) |entry| {
        try keys.append(allocator, entry.key);
        try values.append(allocator, entry.value);
    }
    try std.testing.expectEqual(3, keys.items.len);
    for (&[_][]const u8{ "foo", "foobar", "baz" }, 0..) |expected, idx| {
        try std.testing.expectEqualStrings(expected, keys.items[idx]);
    }
    for (&[_][]const u8{ "v1", "v2", "v3" }, 0..) |expected, idx| {
        try std.testing.expectEqualStrings(expected, values.items[idx]);
    }
}

test "iterate from" {
    const test_alloc = std.testing.allocator;
    var arena_alloc = std.heap.ArenaAllocator.init(test_alloc);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();
    var trie = Trie(i32).init();
    try trie.add(allocator, "foo", 0);
    try trie.add(allocator, "foobar", 1);
    try trie.add(allocator, "foobaz", 2);
    try trie.add(allocator, "foobazqux", 3);
    try trie.add(allocator, "nothing", 4);
    try trie.add(allocator, "foonothing", 5);
    try trie.add(allocator, "foobarbaz", 6);

    var it = try trie.iterateFrom(allocator, "foob");

    var keys = try ArrayList([]const u8).initCapacity(allocator, 4);
    var values = try ArrayList(i32).initCapacity(allocator, 4);
    while (try it.next()) |entry| {
        try keys.append(allocator, entry.key);
        try values.append(allocator, entry.value);
    }
    try std.testing.expectEqual(4, keys.items.len);
    try std.testing.expectEqual(4, values.items.len);
    for (&[_][]const u8{ "foobar", "foobarbaz", "foobaz", "foobazqux" }, 0..) |expected, idx| {
        try std.testing.expectEqualStrings(expected, keys.items[idx]);
    }
    for (&[_]i32{ 1, 6, 2, 3 }, 0..) |expected, idx| {
        try std.testing.expectEqual(expected, values.items[idx]);
    }
}

test "iterate from empty" {
    const test_alloc = std.testing.allocator;
    var arena_alloc = std.heap.ArenaAllocator.init(test_alloc);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();
    var trie = Trie(i32).init();
    try trie.add(allocator, "foo", 0);
    try trie.add(allocator, "bar", 1);
    try trie.add(allocator, "foobar", 2);

    var it = try trie.iterateFrom(allocator, "");

    var keys = try ArrayList([]const u8).initCapacity(allocator, 4);
    var values = try ArrayList(i32).initCapacity(allocator, 4);
    while (try it.next()) |entry| {
        try keys.append(allocator, entry.key);
        try values.append(allocator, entry.value);
    }
    try std.testing.expectEqual(3, keys.items.len);
    try std.testing.expectEqual(3, values.items.len);
    for (&[_][]const u8{ "foo", "foobar", "bar" }, 0..) |expected, idx| {
        try std.testing.expectEqualStrings(expected, keys.items[idx]);
    }
    for (&[_]i32{ 0, 2, 1 }, 0..) |expected, idx| {
        try std.testing.expectEqual(expected, values.items[idx]);
    }
}

test "iterating serialized matches original" {
    const test_alloc = std.testing.allocator;
    var arena_alloc = std.heap.ArenaAllocator.init(test_alloc);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();
    var trie = Trie(WordDataSpec).init();
    try trie.add(allocator, "foo", .{ .start = 0, .len = 3 });
    try trie.add(allocator, "foobar", .{ .start = 1, .len = 6 });
    try trie.add(allocator, "foobaz", .{ .start = 2, .len = 6 });
    try trie.add(allocator, "foobazqux", .{ .start = 3, .len = 9 });
    try trie.add(allocator, "nothing", .{ .start = 4, .len = 7 });
    try trie.add(allocator, "foonothing", .{ .start = 5, .len = 9 });
    try trie.add(allocator, "foobarbaz", .{ .start = 6, .len = 8 });
    try trie.add(allocator, "flow", .{ .start = 7, .len = 4 });

    const serialized = try serializeTrie(allocator, trie);

    var trie_data: std.ArrayList(WordDataSpec) = .{};
    var serialized_data: std.ArrayList(WordDataSpec) = .{};
    var trie_it = try trie.iterateFrom(allocator, "fo");
    var serialized_it = try iterateSerializedTrie(allocator, serialized, "fo");

    while (try trie_it.next()) |spec| {
        try trie_data.append(allocator, spec.value);
    }
    while (try serialized_it.next()) |spec| {
        try serialized_data.append(allocator, spec.spec);
    }
    try std.testing.expectEqualSlices(WordDataSpec, trie_data.items, serialized_data.items);
}
