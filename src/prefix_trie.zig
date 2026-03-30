const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const ArrayList = @import("std").ArrayList;
const words = @import("words.zig");

pub fn Trie(comptime T: type) type {
    return struct {
        const Self = @This();

        root: TrieNode(T),

        pub fn init() Trie(T) {
            return .{ .root = TrieNode(T).init() };
        }

        pub fn add(self: *Self, allocator: Allocator, key: []const u8, value: T) !void {
            return self.root.add(allocator, key, key, value);
        }

        pub fn get(self: *Self, key: []const u8) ?T {
            const node = self.root.get(key) orelse return null;
            return node.value;
        }

        pub fn iterator(self: *const Self, allocator: Allocator) !Iterator {
            return iterateFromNode(allocator, self.root);
        }

        pub fn iterateFrom(self: *const Self, allocator: Allocator, key: []const u8) !Iterator {
            const node = self.root.get(key) orelse return .{ .stack = .{}, .allocator = allocator };
            return iterateFromNode(allocator, node);
        }

        fn iterateFromNode(allocator: Allocator, node: TrieNode(T)) !Iterator {
            var stack = try ArrayList(TrieNode(T)).initCapacity(allocator, 32);
            try stack.append(allocator, node);
            return .{ .stack = stack, .allocator = allocator };
        }

        pub const Iterator = struct {
            stack: ArrayList(TrieNode(T)),
            allocator: Allocator,

            pub fn next(it: *Iterator) !?Entry {
                var key: ?[]const u8 = null;
                var value: ?T = null;
                while (key == null) {
                    const node = it.stack.pop() orelse return null;
                    var idx = node.children.items.len;
                    // we push in the reverse order just so iteration is done in the order
                    // children got added
                    while (idx > 0) {
                        idx -= 1;
                        const child = node.children.items[idx];
                        try it.stack.append(it.allocator, child.node);
                    }
                    key = node.key;
                    value = node.value;
                }
                return .{ .key = key.?, .value = value.? };
            }
        };

        pub const Entry = struct {
            key: []const u8,
            value: T,
        };
    };
}

fn NodePair(comptime T: type) type {
    return struct {
        key: u8,
        node: TrieNode(T),
    };
}

fn TrieNode(comptime T: type) type {
    return struct {
        const Self = @This();

        key: ?[]const u8,
        value: ?T,
        children: ArrayList(NodePair(T)),

        pub fn init() Self {
            return .{ .key = null, .value = null, .children = .{} };
        }

        pub fn get(self: *const Self, key: []const u8) ?Self {
            if (key.len == 0) {
                return self.*;
            }
            if (self.getChild(key[0])) |child| {
                return child.get(key[1..]);
            }
            return null;
        }

        pub fn add(self: *Self, allocator: Allocator, partial_key: []const u8, key: []const u8, value: T) !void {
            if (partial_key.len == 0) {
                self.key = key;
                self.value = value;
                return;
            }
            var node: ?*Self = self.getChild(partial_key[0]);
            if (node == null) {
                // create a new child node because the required one does not exist.
                const idx = self.children.items.len;
                try self.children.append(allocator, .{ .key = partial_key[0], .node = init() });
                node = &(self.children.items[idx].node);
            }
            try node.?.add(allocator, partial_key[1..], key, value);
        }

        pub fn getChild(self: Self, child_key: u8) ?*Self {
            for (self.children.items) |*child| {
                const v = child.key;
                if (v == child_key) {
                    return &child.node;
                }
            }
            return null;
        }
    };
}

pub const WordDataSpec = struct {
    start: u32 = 0,
    len: u32 = 0,
};

const SerializedNodeHeader = struct {
    value_offset: u32,
    value_size: u32,
    child_count: u32,
};

const SerializedChild = struct {
    key: u8,
    node_offset: u32,
};

fn Indexed(comptime T: type) type {
    return struct {
        data: T,
        offset: usize,
    };
}

fn unpaddedSize(comptime T: type) usize {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            var total_size: usize = 0;
            inline for (info.fields) |field| {
                total_size += unpaddedSize(field.type);
            }
            return total_size;
        },
        else => return @sizeOf(T),
    }
}

fn serializeType(comptime T: type, buffer: []u8, value: T) usize {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        const size = @sizeOf(T);
        std.mem.writeInt(T, buffer[0..size], value, .little);
        return size;
    }
    var offset: usize = 0;
    inline for (info.@"struct".fields) |field| {
        const size = serializeType(field.type, buffer[offset..][0..unpaddedSize(field.type)], @field(value, field.name));
        offset += size;
    }
    return offset;
}

fn deserializeType(comptime T: type, bytes: []const u8) T {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        return std.mem.readInt(T, bytes[0..@sizeOf(T)], .little);
    }
    var offset: usize = 0;
    var result: T = std.mem.zeroes(T);
    inline for (info.@"struct".fields) |field| {
        const size = unpaddedSize(field.type);
        const value = deserializeType(field.type, bytes[offset..][0..size]);
        @field(result, field.name) = value;
        offset += size;
    }
    return result;
}

pub fn serializeTrie(allocator: Allocator, trie: Trie(WordDataSpec)) ![]const u8 {
    var data: ArrayList(u8) = .{};
    _ = try serializeTrieRec(allocator, trie.root, &data);
    return data.items;
}

fn serializeTrieRec(allocator: Allocator, node: TrieNode(WordDataSpec), data: *ArrayList(u8)) !u32 {
    const word_spec: WordDataSpec = node.value orelse .{};
    const header_offset: u32 = @intCast(data.items.len);
    const header: SerializedNodeHeader = .{
        .value_offset = @intCast(word_spec.start),
        .value_size = @intCast(word_spec.len),
        .child_count = @intCast(node.children.items.len),
    };

    // reserve space in the data array for the header
    const header_bytes = [_]u8{0} ** unpaddedSize(SerializedNodeHeader);
    try data.appendSlice(allocator, &header_bytes);
    var child_offset = header_offset + serializeType(SerializedNodeHeader, data.items[header_offset..], header);

    const children_bytes = try allocator.alloc(u8, unpaddedSize(SerializedChild) * header.child_count);
    try data.appendSlice(allocator, children_bytes);

    // for each child, process the child and write its offset to the children_bytes
    for (node.children.items) |child| {
        const offset = try serializeTrieRec(allocator, child.node, data);
        const child_header: SerializedChild = .{ .key = child.key, .node_offset = offset };
        child_offset += serializeType(SerializedChild, data.items[child_offset..], child_header);
    }
    return header_offset;
}

pub fn getFromSerializedTrie(serialized: []const u8, key: []const u8) !?WordDataSpec {
    const wrapped = navigateToSubTrie(serialized, key) orelse return null;
    const node = wrapped.data;
    return .{ .start = node.value_offset, .len = node.value_size };
}

pub const KeyedWordDataSpec = struct {
    spec: WordDataSpec,
    key: []const u8,
};

const SerializedTrieIterator = struct {
    stack: ArrayList(Indexed(SerializedNodeHeader)),
    key_stack: ArrayList([]const u8),
    allocator: Allocator,
    buffer: []const u8,

    pub fn next(it: *SerializedTrieIterator) !?KeyedWordDataSpec {
        var spec: WordDataSpec = .{};
        var key: []u8 = &[_]u8{};
        while (spec.len == 0) {
            const node = it.stack.pop() orelse return null;
            const partial_key = it.key_stack.pop() orelse return null;
            defer it.allocator.free(partial_key);
            const children_offset = node.offset + unpaddedSize(SerializedNodeHeader);
            var child_idx = node.data.child_count;
            while (child_idx > 0) {
                child_idx -= 1;
                const child_size = unpaddedSize(SerializedChild);
                const child_offset = children_offset + child_idx * child_size;
                const child_node = deserializeType(SerializedChild, it.buffer[child_offset .. child_offset + child_size]);

                var child_key: []u8 = try it.allocator.alloc(u8, partial_key.len + 1);
                std.mem.copyForwards(u8, child_key, partial_key);
                child_key[child_key.len - 1] = child_node.key;

                const header_size = unpaddedSize(SerializedNodeHeader);
                const target_node = deserializeType(SerializedNodeHeader, it.buffer[child_node.node_offset .. child_node.node_offset + header_size]);

                try it.stack.append(it.allocator, .{ .data = target_node, .offset = child_node.node_offset });
                try it.key_stack.append(it.allocator, child_key);
            }
            spec = .{ .start = node.data.value_offset, .len = node.data.value_size };
            key = try it.allocator.alloc(u8, partial_key.len);
            std.mem.copyForwards(u8, key, partial_key);
        }
        return .{ .spec = spec, .key = key };
    }
};

fn navigateToSubTrie(buffer: []const u8, key: []const u8) ?Indexed(SerializedNodeHeader) {
    var position: usize = 0;
    var sub_key = key;
    while (true) {
        // TODO restructure this loop
        const header_size = unpaddedSize(SerializedNodeHeader);
        const header = deserializeType(SerializedNodeHeader, buffer[position .. position + header_size]);
        if (sub_key.len == 0) {
            return .{ .data = header, .offset = position };
        }
        position += header_size;
        const key_char = sub_key[0];
        sub_key = sub_key[1..sub_key.len];

        for (0..header.child_count) |_| {
            const child_size = unpaddedSize(SerializedChild);
            const child_node = deserializeType(SerializedChild, buffer[position .. position + child_size]);
            position += child_size;
            if (child_node.key == key_char) {
                position = child_node.node_offset;
                break;
            }
        } else {
            // there is no value or subtrie for this key
            return null;
        }
    }
}

pub fn iterateSerializedTrie(allocator: Allocator, buffer: []const u8, start: []const u8) !SerializedTrieIterator {
    const root = navigateToSubTrie(buffer, start) orelse return .{
        .stack = .{},
        .key_stack = .{},
        .allocator = allocator,
        .buffer = buffer,
    };
    // Our iterator allocates and then frees incremental keys that it adds and pops from the stack
    // and might try to free the passed in "start" buffer - copy the key so this is fine.
    const key = try allocator.alloc(u8, start.len);
    std.mem.copyForwards(u8, key, start);
    var stack: ArrayList(Indexed(SerializedNodeHeader)) = .{};
    var key_stack: ArrayList([]const u8) = .{};
    try stack.append(allocator, root);
    try key_stack.append(allocator, key);
    return .{
        .stack = stack,
        .key_stack = key_stack,
        .allocator = allocator,
        .buffer = buffer,
    };
}
