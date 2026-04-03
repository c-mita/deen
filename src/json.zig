const std = @import("std");
const Definition = @import("lib.zig").Definition;
const Sense = @import("lib.zig").Sense;

pub const WordSense = struct {
    glosses: ?[]const []const u8 = null,
    raw_glosses: ?[]const []const u8 = null,
};

pub const WordEntry = struct {
    word: []const u8,
    pos: []const u8,
    lang_code: []const u8,
    senses: []const WordSense,
};

pub fn isGermanWord(entry: WordEntry) bool {
    if (!std.mem.eql(u8, "de", entry.lang_code)) return false;
    if (std.mem.eql(u8, "name", entry.pos)) return false;
    if (std.mem.eql(u8, "character", entry.pos)) return false;
    return true;
}

pub fn interpreteWord(allocator: std.mem.Allocator, entry: WordEntry) !Definition {
    const word = entry.word;
    const pos = entry.pos;
    var sense_data = try std.ArrayList(Sense).initCapacity(allocator, 8);
    for (entry.senses) |sense| {
        // prefer raw_glosses if it exists since it contains tag information
        const raw_glosses = sense.raw_glosses orelse &[_][]const u8{};
        const glosses = if (raw_glosses.len > 0) raw_glosses else sense.glosses orelse &[_][]const u8{};
        if (glosses.len == 0) {
            continue;
        }
        const gloss = glosses[0];
        const subglosses = if (glosses.len > 1) glosses[1..] else &[_][]const u8{};

        if (subglosses.len > 0) {
            // find the existing sense and add the new subsense
            for (sense_data.items) |*existing| {
                if (!std.mem.eql(u8, existing.sense, gloss)) continue;
                try existing.subsenses.appendSlice(allocator, subglosses);
                break;
            } else {
                const subsenses = try std.ArrayList([]const u8).initCapacity(allocator, subglosses.len);
                try sense_data.append(allocator, .{ .sense = gloss, .subsenses = subsenses });
            }
        } else {
            try sense_data.append(allocator, .{ .sense = gloss, .subsenses = std.ArrayList([]const u8).empty });
        }
    }
    return .{ .word = word, .type = pos, .senses = sense_data.items };
}
