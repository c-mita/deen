const std = @import("std");
const WordDataSpec = @import("lib.zig").WordDataSpec;
const getFromSerializedTrie = @import("lib.zig").getFromSerializedTrie;
const iterateSerializedTrie = @import("lib.zig").iterateSerializedTrie;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gen_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gen_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();

    const trie_file_path = try (args.next() orelse error.MissingArgument);
    const definition_file_path = try (args.next() orelse error.MissingArgument);
    const target_word = try (args.next() orelse error.MissingArgument);

    const trie_file = try std.fs.cwd().openFile(trie_file_path, .{});
    const trie_bytes_size = (try trie_file.stat()).size;

    const trie_bytes = try std.posix.mmap(
        null,
        trie_bytes_size,
        std.posix.PROT.READ,
        .{ .TYPE = .SHARED },
        trie_file.handle,
        0,
    );
    defer std.posix.munmap(trie_bytes);

    const spec: WordDataSpec = try getFromSerializedTrie(trie_bytes, target_word) orelse .{};

    const definition_file = try std.fs.cwd().openFile(definition_file_path, .{});
    const definition_file_size = (try definition_file.stat()).size;
    const definition_bytes = try std.posix.mmap(
        null,
        definition_file_size,
        std.posix.PROT.READ,
        .{ .TYPE = .SHARED },
        definition_file.handle,
        0,
    );
    const definition = definition_bytes[spec.start .. spec.start + spec.len];
    std.debug.print("{any}\n", .{spec});
    std.debug.print("{s}\n", .{definition});

    var iterator = try iterateSerializedTrie(allocator, trie_bytes, target_word);
    while (try iterator.next()) |key| {
        std.debug.print("{s}\n", .{key.key});
    }
}
