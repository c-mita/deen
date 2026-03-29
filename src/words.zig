const std = @import("std");

pub const Sense = struct {
    sense: []const u8,
    subsenses: std.ArrayList([]const u8),
};

pub const Definition = struct {
    word: []const u8,
    type: []const u8,
    senses: []const Sense,
};

pub fn collateEntries(allocator: std.mem.Allocator, entries: []Definition) !std.StringHashMapUnmanaged([]u8) {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var current_word: []const u8 = &.{};
    var writer: std.io.Writer.Allocating = .init(arena_alloc);
    var output_map = std.StringHashMapUnmanaged([]u8){};
    for (entries) |entry| {
        if (!std.mem.eql(u8, current_word, entry.word)) {
            if (output_map.contains(entry.word)) {
                std.debug.print("'{s}' has already been processed\n", .{entry.word});
                return error.AlreadyProcessed;
            }
            if (current_word.len > 0) {
                const written_data = writer.toArrayList().items;
                const buffer = try allocator.alloc(u8, written_data.len);
                std.mem.copyForwards(u8, buffer, written_data);
                try output_map.put(allocator, current_word, buffer);
            }
            current_word = entry.word;
            writer.deinit();
            writer = std.io.Writer.Allocating.init(arena_alloc);
        }
        try printEntry(&writer.writer, entry);
    }
    return output_map;
}

pub fn printEntry(writer: *std.Io.Writer, entry: Definition) !void {
    try writer.print("{s} - {s}\n", .{ entry.word, entry.type });
    for (entry.senses) |sense| {
        try writer.print(" - {s}\n", .{sense.sense});
        for (sense.subsenses.items) |subsense| {
            try writer.print(" - - {s}\n", .{subsense});
        }
    }
}
