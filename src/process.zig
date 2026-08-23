const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const ArrayList = @import("std").ArrayList;
const json = @import("json.zig");
const collateEntries = @import("lib.zig").collateEntries;
const Definition = @import("lib.zig").Definition;
const Sense = @import("lib.zig").Sense;
const Trie = @import("lib.zig").Trie;
const WordDataSpec = @import("lib.zig").WordDataSpec;
const serializeTrie = @import("lib.zig").serializeTrie;
const getFromSerializedTrie = @import("lib.zig").getFromSerializedTrie;

fn structureData(
    allocator: Allocator,
    entry_map: std.StringHashMapUnmanaged([]u8),
) !struct { std.StringHashMapUnmanaged(WordDataSpec), []const u8 } {
    var definition_data: ArrayList(u8) = try .initCapacity(allocator, 1024 * 1024);
    var word_map: std.StringHashMapUnmanaged(WordDataSpec) = .{};

    var iterator = entry_map.iterator();
    var current: u32 = 0;
    while (iterator.next()) |entry| {
        const word = entry.key_ptr.*;
        const data = entry.value_ptr.*;
        try definition_data.appendSlice(allocator, data);
        try word_map.put(allocator, word, .{ .start = current, .len = @intCast(data.len) });
        current += @intCast(data.len);
    }
    return .{ word_map, definition_data.items };
}

/// Determine if the given sense text suggests this is a non-standard spelling of another
/// word (e.g. because it's Swiss or for when keys like ß are not available)
fn isRespelling(sense_text: []const u8) bool {
    const spelling_of = std.mem.containsAtLeast(u8, sense_text, 1, "spelling of");
    const unavailable = std.mem.containsAtLeast(u8, sense_text, 1, "unavailable");
    const switzerland = std.mem.containsAtLeast(u8, sense_text, 1, "Switzerland");
    const liechtenstein = std.mem.containsAtLeast(u8, sense_text, 1, "Liechtenstein");
    // "Former standard spelling of ..."
    const former = std.mem.containsAtLeast(u8, sense_text, 1, "Former");
    const likely = former | unavailable | switzerland | liechtenstein;
    return spelling_of & likely;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var gen_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gen_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    var trie_file: []const u8 = &[_]u8{};
    var definition_file: []const u8 = &[_]u8{};
    _ = args.skip();
    const first_arg = args.next();
    const second_arg = args.next();
    if (first_arg == null or second_arg == null) {
        std.debug.print("Require output trie and definition file paths\n", .{});
        return error.InvalidCommandLine;
    }
    trie_file = first_arg.?;
    definition_file = second_arg.?;

    const stdin = std.fs.File.stdin();

    // some of the JSON lines are quite big, so we need a big read buffer
    const stdin_read_buf: []u8 = try gen_alloc.alloc(u8, 1024 * 1024 * 8);
    var stdin_reader = stdin.readerStreaming(stdin_read_buf);

    var word_list = try ArrayList(Definition).initCapacity(allocator, 1024);
    var omitted_words: std.StringArrayHashMapUnmanaged(bool) = .{};
    while (true) {
        var scratch_arena = std.heap.ArenaAllocator.init(allocator);
        const scratch_alloc = scratch_arena.allocator();
        defer scratch_arena.deinit();
        const line = stdin_reader.interface.takeDelimiterInclusive('\n') catch |err| {
            if (err == error.EndOfStream) break else return err;
        };
        const parsed = try std.json.parseFromSlice(json.WordEntry, scratch_alloc, line, .{
            .allocate = std.json.AllocWhen.alloc_always,
            .ignore_unknown_fields = true,
        });
        const json_entry = parsed.value;
        if (!json.isGermanWord(json_entry)) {
            continue;
        }
        if (json_entry.senses.len == 0) {
            continue;
        }
        const word_def = try json.interpreteWord(allocator, json_entry);
        // skip senseless defintions
        if (word_def.senses.len == 0) {
            continue;
        }

        // identify senses that are "Swiss" alternate spellings (or otherwise
        // just substitute ß for ss) - having these in the Trie ruins tab completion
        // (looking at you Fussballweltmeisterschaftsqualifikationsspiel)
        // We assume such words will only have a single sense, marking the non-standard spelling
        if (word_def.senses.len == 1) {
            const sense = word_def.senses[0];
            // Only check words that have listed "alternates"
            if (sense.alternate_of.len != 0) {
                if (isRespelling(sense.sense)) {
                    try omitted_words.put(allocator, word_def.word, true);
                    continue;
                }
            }
        }
        try word_list.append(allocator, word_def);
    }

    // Filter out words that are only a form of an omitted word
    var filtered_word_list: std.ArrayList(Definition) = .{};
    for (word_list.items) |word| {
        sense_loop: for (word.senses) |sense| {
            if (isRespelling(sense.sense)) {
                continue;
            }
            if (sense.form_of.len == 0) {
                try filtered_word_list.append(allocator, word);
                break :sense_loop;
            }
            for (sense.form_of) |alternate| {
                // any sense that is not a form of an omitted word and is not a respelling is a
                // good enough reason to keep the word
                if (!omitted_words.contains(alternate)) {
                    try filtered_word_list.append(allocator, word);
                    break :sense_loop;
                }
            }
        }
    }
    word_list.clearAndFree(allocator);
    word_list = filtered_word_list;

    var trie = Trie(WordDataSpec).init();
    const word_defs = try collateEntries(allocator, word_list.items);
    const word_def_map, const definition_data = try structureData(allocator, word_defs);
    var def_iterator = word_def_map.iterator();
    while (def_iterator.next()) |entry| {
        const word = entry.key_ptr.*;
        const spec = entry.value_ptr.*;
        try trie.add(allocator, word, spec);
    }

    const serialized = try serializeTrie(allocator, trie);
    var trie_out_file = try std.fs.cwd().createFile(trie_file, .{});
    try trie_out_file.writeAll(serialized);

    var text_out_file = try std.fs.cwd().createFile(definition_file, .{});
    try text_out_file.writeAll(definition_data);
}
