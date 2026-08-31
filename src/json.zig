const std = @import("std");
const Definition = @import("lib.zig").Definition;
const Sense = @import("lib.zig").Sense;

pub const WordSense = struct {
    glosses: ?[]const []const u8 = null,
    raw_glosses: ?[]const []const u8 = null,
    alt_of: ?[]const OfWord = null,
    form_of: ?[]const OfWord = null,
};

pub const OfWord = struct {
    /// sense.alt_of and senes.form_of are a list dicts with the key "word" being
    /// the only interesting one
    word: []const u8,
};

pub const WordHeadTemplate = struct {
    name: []const u8,
    expansion: []const u8,
};

pub const WordEntry = struct {
    word: []const u8,
    pos: []const u8,
    lang_code: []const u8,
    head_templates: []const WordHeadTemplate = &.{},
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
    var headers: std.ArrayList([]const u8) = .empty;
    // search for head_templates with the name "de-[pos]" - theses are usually interesting
    // typically there's only one, but sometimes there are more (e.g. for "der Butter")
    for (entry.head_templates) |head_template| {
        if (std.mem.eql(u8, head_template.name[0..3], "de-") and std.mem.eql(u8, head_template.name[3..], entry.pos)) {
            try headers.append(allocator, head_template.expansion);
        }
    }
    var sense_data = try std.ArrayList(Sense).initCapacity(allocator, 8);
    for (entry.senses) |sense| {
        var word_alternates: std.ArrayList([]const u8) = .empty;
        const alts = sense.alt_of orelse &[_] OfWord{};
        for (alts) |alt_word| {
            try word_alternates.append(allocator, alt_word.word);
        }

        var word_forms: std.ArrayList([]const u8) = .empty;
        const forms = sense.form_of orelse &[_] OfWord{};
        for (forms) |form| {
            try word_forms.append(allocator, form.word);
        }

        // prefer raw_glosses if it exists since it contains tag information
        const raw_glosses = sense.raw_glosses orelse &[_][]const u8{};
        const glosses = if (raw_glosses.len > 0) raw_glosses else sense.glosses orelse &[_][]const u8{};
        if (glosses.len == 0) {
            continue;
        }
        const gloss = glosses[0];
        const subglosses = if (glosses.len > 1) glosses[1..] else &[_][]const u8{};

        if (subglosses.len > 0) {
            // find the matching sense if it exists and add the new subsense
            var subsenses: *std.ArrayList([]const u8) = undefined;
            for (sense_data.items) |*existing| {
                if (!std.mem.eql(u8, existing.sense, gloss)) continue;
                subsenses = &existing.subsenses;
                break;
            } else {
                const new_subsenses = try std.ArrayList([]const u8).initCapacity(allocator, subglosses.len);
                try sense_data.append(
                    allocator,
                    .{
                        .sense = gloss,
                        .subsenses = new_subsenses,
                        .alternate_of = word_alternates.items,
                        .form_of = word_forms.items,
                    });
                subsenses = &sense_data.items[sense_data.items.len - 1].subsenses;
            }
            try subsenses.appendSlice(allocator, subglosses);
        } else {
            try sense_data.append(
                allocator,
                .{
                    .sense = gloss,
                    .subsenses = std.ArrayList([]const u8).empty,
                    .alternate_of = word_alternates.items,
                    .form_of = word_forms.items,
                });
        }
    }
    return .{ .word = word, .type = pos, .headers = headers.items, .senses = sense_data.items };
}
