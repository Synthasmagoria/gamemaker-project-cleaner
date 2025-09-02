const std = @import("std");
const c = @import("c.zig").c;
const Allocator = std.mem.Allocator;

const json5_error = c.zpl_u8;

pub const AdtNodeType = enum {
    Unitialized,
    Array,
    Object,
    String,
    Multistring,
    Integer,
    Real,
};

pub const AdtNode = extern struct {
    name: [*:0]const u8,
    parent: *AdtNode,
    properties: packed struct {
        type: u4,
        props: u4
    },
    data: extern union {
        string: [*:0]const u8,
        nodes: [*]AdtNode,
        value: extern union {
            real: f64,
            integer: i64
        }
    },

    pub fn query(node: *AdtNode, query_str: [:0]const u8) ?*AdtNode {
        const zpl_node = c.zpl_adt_query(@ptrCast(@alignCast(node)), query_str.ptr);
        if (zpl_node == null) {
            return null;
        }
        return @ptrCast(@alignCast(zpl_node));
    }

    pub fn query_type(node: *AdtNode, query_str: [:0]const u8, node_type: AdtNodeType) ?*AdtNode {
        const zpl_node = c.zpl_adt_query(@ptrCast(@alignCast(node)), query_str.ptr);
        if (zpl_node == null) {
            return null;
        }
        const n: ?*AdtNode = @ptrCast(@alignCast(zpl_node));
        if (!n.?.is_type(node_type)) {
            return null;
        }
        return n;
    }

    pub fn is_type(node: *AdtNode, node_type: AdtNodeType) bool {
        return node.properties.type == @intFromEnum(node_type);
    }

    pub fn get_array_header(node: *AdtNode) c.zpl_array_header {
        std.debug.assert(node.is_type(AdtNodeType.Array));
        const header_pointer = @as([*]c.zpl_array_header, @ptrCast(@alignCast(node.data.nodes)));
        return @as(*c.zpl_array_header, @ptrCast(header_pointer - @as(usize, 1))).*;
    }

    pub fn get_array_child(node: *AdtNode, i: usize) *AdtNode {
        std.debug.assert(node.is_type(AdtNodeType.Array));
        return &node.data.nodes[i];
    }
};

pub fn parse_json5(alloc: Allocator, zpl_alloc: c.zpl_allocator, abs_path: []const u8, out: *AdtNode) !json5_error {
    const f = try std.fs.openFileAbsolute(abs_path, .{});
    defer f.close();
    const json5 = try f.readToEndAlloc(alloc, std.math.maxInt(usize));
    defer c.zpl_free_all(zpl_alloc);
    return c.zpl_json_parse(@ptrCast(out), json5.ptr, zpl_alloc);
}
