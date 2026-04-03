const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const ArrayList = @import("std").ArrayList;
const WordDataSpec = @import("lib.zig").WordDataSpec;
const getFromSerializedTrie = @import("lib.zig").getFromSerializedTrie;
const iterateSerializedTrie = @import("lib.zig").iterateSerializedTrie;

const Parameters = struct {
    keys: [][]const u8,
    search_key: []const u8,
    walk: bool,
    retrieve: bool,
    allow_empty: bool,
};

fn parseArguments(allocator: Allocator) !Parameters {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var walk: bool = false;
    var retrieve: bool = true;
    var allow_empty: bool = false;
    var keys: ArrayList([]const u8) = .{};
    var search_key: []const u8 = &[_]u8{};

    var args = try std.process.argsWithAllocator(arena_alloc);
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, "--walk", arg)) {
            walk = true;
            retrieve = false;
        } else if (std.mem.eql(u8, "--allow_empty", arg)) {
            allow_empty = true;
        } else {
            if (arg.len == 0) {
                try keys.append(allocator, arg);
            } else {
                const key: []u8 = try allocator.alloc(u8, arg.len);
                std.mem.copyForwards(u8, key, arg);
                try keys.append(allocator, key);
            }
        }
    }
    if (walk and keys.items.len > 1) {
        return error.InvalidArguments;
    }
    if (walk and keys.items.len == 1) {
        search_key = keys.items[0];
    }
    return .{
        .keys = keys.items,
        .search_key = search_key,
        .walk = walk,
        .retrieve = retrieve,
        .allow_empty = allow_empty,
    };
}

const SubIterator = struct {
    sub_positions: [15]u8,
    word: []const u8,
    working_word: []u8,
    max: u16,
    current: u16,

    /// The string returned is transient and changed by subsequent next() calls.
    /// Copy the string if you need it for longer.
    fn next(it: *SubIterator) ?[]const u8 {
        if (it.current > it.max) {
            return null;
        }
        std.mem.copyForwards(u8, it.working_word, it.word);
        var idx: u4 = 0;
        for (it.sub_positions) |pos| {
            const set = (@as(u16, 1) << idx) & it.current;
            idx += 1;
            if (set == 0) {
                continue;
            }
            const v1 = it.word[pos];
            const v2 = it.word[pos + 1];
            if (v1 == 'A' and v2 == 'e') {
                it.working_word[pos] = 0xC3;
                it.working_word[pos + 1] = 0x84;
            } else if (v1 == 'a' and v2 == 'e') {
                it.working_word[pos] = 0xC3;
                it.working_word[pos + 1] = 0xA4;
            } else if (v1 == 'O' and v2 == 'e') {
                it.working_word[pos] = 0xC3;
                it.working_word[pos + 1] = 0x96;
            } else if (v1 == 'o' and v2 == 'e') {
                it.working_word[pos] = 0xC3;
                it.working_word[pos + 1] = 0xB6;
            } else if (v1 == 'U' and v2 == 'e') {
                it.working_word[pos] = 0xC3;
                it.working_word[pos + 1] = 0x9C;
            } else if (v1 == 'u' and v2 == 'e') {
                it.working_word[pos] = 0xC3;
                it.working_word[pos + 1] = 0xBC;
            } else if (v1 == 's' and v2 == 's') {
                it.working_word[pos] = 0xC3;
                it.working_word[pos + 1] = 0x9F;
            }
        }
        it.current += 1;
        return it.working_word;
    }

    fn deinit(it: *SubIterator, allocator: Allocator) void {
        allocator.free(it.working_word);
    }
};

fn potentialReverseSubstitutions(allocator: Allocator, word: []const u8) !SubIterator {
    const working_word = try allocator.alloc(u8, word.len);
    std.mem.copyForwards(u8, working_word, word);
    var positions: [15]u8 = [_]u8{0} ** 15;
    var idx: u8 = 0;
    var p_idx: u4 = 0;
    while (idx < word.len - 1) {
        const v1 = word[idx];
        const v2 = word[idx + 1];
        var can_sub = false;
        if (v2 == 'e' and (v1 == 'A' or v1 == 'a' or v1 == 'O' or v1 == 'o' or v1 == 'U' or v1 == 'u')) {
            can_sub = true;
        } else if (v1 == 's' and v2 == 's') {
            can_sub = true;
        }
        if (can_sub) {
            if (p_idx == positions.len) {
                return error.TooManySubstitutions;
            }
            positions[p_idx] = idx;
            p_idx += 1;
            idx += 1;
        }
        idx += 1;
    }
    const max = (@as(u16, 1) << p_idx) - 1;
    return .{
        .sub_positions = positions,
        .word = word,
        .working_word = working_word,
        .max = max,
        .current = 0,
    };
}

pub fn main() !void {
    const trie_data: []const u8 align(4096) = @embedFile("data.trie");
    const definition_data: []const u8 align(4096) = @embedFile("data.dat");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gen_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gen_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout = std.fs.File.stdout();
    var write_buf: [128]u8 = undefined;
    var stdout_writer = stdout.writer(&write_buf);
    defer stdout_writer.interface.flush() catch {};

    const parameters = parseArguments(allocator) catch |err| {
        if (err == error.InvalidArguments) {
            try stdout_writer.interface.print("deen [--allow_empty] [--walk word] words...\n", .{});
        }
        return err;
    };
    if (parameters.walk) {
        const target_word = if (parameters.keys.len > 0) parameters.keys[0] else "";
        if (target_word.len > 0 or parameters.allow_empty) {
            var subs = try potentialReverseSubstitutions(allocator, target_word);
            while (subs.next()) |word| {
                var iterator = try iterateSerializedTrie(allocator, trie_data, word);
                while (try iterator.next()) |key| {
                    try stdout_writer.interface.print("{s}\n", .{key.key});
                }
            }
        }
    }

    if (parameters.retrieve) {
        for (parameters.keys) |target_word| {
            var subs = try potentialReverseSubstitutions(allocator, target_word);
            while (subs.next()) |word| {
                if (try getFromSerializedTrie(trie_data, word)) |spec| {
                    const defintion = definition_data[spec.start .. spec.start + spec.len];
                    try stdout_writer.interface.print("{s}\n", .{defintion});
                }
            }
        }
    }
}

test "iterate substitutions" {
    const test_alloc = std.testing.allocator;
    var arena_alloc = std.heap.ArenaAllocator.init(test_alloc);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();

    var it = try potentialReverseSubstitutions(allocator, "Aebsslueb");
    defer it.deinit(allocator);
    const expected = [_][]const u8{
        "Aebsslueb",
        "Äbsslueb",
        "Aebßlueb",
        "Äbßlueb",
        "Aebsslüb",
        "Äbsslüb",
        "Aebßlüb",
        "Äbßlüb",
    };
    var idx: u32 = 0;
    while (it.next()) |actual| {
        try std.testing.expectEqualStrings(expected[idx], actual);
        idx += 1;
    }
}

test "no substitutions" {
    const test_alloc = std.testing.allocator;
    var arena_alloc = std.heap.ArenaAllocator.init(test_alloc);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();
    var it = try potentialReverseSubstitutions(allocator, "foobar");
    defer it.deinit(allocator);

    const first = it.next().?;
    try std.testing.expectEqualStrings("foobar", first);
    try std.testing.expectEqual(null, it.next());
}

test "too many substitutions" {
    const test_alloc = std.testing.allocator;
    var arena_alloc = std.heap.ArenaAllocator.init(test_alloc);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();
    try std.testing.expectError(
        error.TooManySubstitutions,
        potentialReverseSubstitutions(allocator, "aeoeuessaeoeuessaeoeuessaeoeuess"),
    );
}
