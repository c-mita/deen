const std = @import("std");

pub const FilterEntry = struct {
    pos: []const u8,
    lang_code: []const u8,
};

pub fn isNotGermanWord(entry: FilterEntry) bool {
    if (!std.mem.eql(u8, "de", entry.lang_code)) return true;
    if (std.mem.eql(u8, "name", entry.pos)) return true;
    if (std.mem.eql(u8, "character", entry.pos)) return true;
    return false;
}

pub fn main() !void {
    const stdout = std.fs.File.stdout();
    var write_buf: [128]u8 = undefined;
    var stdout_writer = stdout.writer(&write_buf);
    defer stdout_writer.interface.flush() catch {};

    const stdin = std.fs.File.stdin();
    var stdin_buf: [8 * 1024 * 1024]u8 = undefined;
    var stdin_reader = stdin.readerStreaming(&stdin_buf);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gen_alloc = gpa.allocator();

    while (true) {
        const line = stdin_reader.interface.takeDelimiterInclusive('\n') catch |err| {
            if (err == error.EndOfStream) break else return err;
        };

        const parsed = std.json.parseFromSlice(
            FilterEntry,
            gen_alloc,
            line,
            .{ .ignore_unknown_fields = true },
        ) catch |err| {
            if (err == error.MissingField) continue else return err;
        };
        if (!isNotGermanWord(parsed.value)) {
            try stdout_writer.interface.writeAll(line);
        }
    }
}
