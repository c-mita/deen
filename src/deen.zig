const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const ArrayList = @import("std").ArrayList;
const WordDataSpec = @import("prefix_trie.zig").WordDataSpec;
const getFromSerializedTrie = @import("prefix_trie.zig").getFromSerializedTrie;
const iterateSerializedTrie = @import("prefix_trie.zig").iterateSerializedTrie;

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
            var iterator = try iterateSerializedTrie(allocator, trie_data, target_word);
            while (try iterator.next()) |key| {
                try stdout_writer.interface.print("{s}\n", .{key.key});
            }
        }
    }

    if (parameters.retrieve) {
        for (parameters.keys) |target_word| {
            const spec: WordDataSpec = try getFromSerializedTrie(trie_data, target_word) orelse .{};
            const defintion = definition_data[spec.start .. spec.start + spec.len];
            try stdout_writer.interface.print("{s}\n", .{defintion});
        }
    }
}
