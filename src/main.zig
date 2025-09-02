const std = @import("std");
const fs = std.fs;
const c = @import("c.zig").c;
const arguments = @import("args.zig");

const char = u8;

fn prints(str: []const char) void {
    std.debug.print("{s}\n", .{str});
}

fn printerr(comptime fmt: []const char, args: anytype) !void {
    try stderr.print("error: " ++ fmt ++ "\n", args);
    try stderr.flush();
}

fn printinfo(comptime fmt: []const char, args: anytype) !void {
    try stdout.print("info: " ++ fmt ++ "\n", args);
    try stdout.flush();
}

const usageMessage = "usage: gamemaker-path-corrector <absolute-project-file-path>";
const helpMessage = "--- GAMEMAKER PROJECT CLEANER ---\n" ++ usageMessage;

const IO_BUFFER_SIZE = 1024;
var stderr_buffer: [IO_BUFFER_SIZE]char = undefined;
var stderr_writer: fs.File.Writer = undefined;
var stderr: *std.io.Writer = undefined;

var stdout_buffer: [IO_BUFFER_SIZE]char = undefined;
var stdout_writer: fs.File.Writer = undefined;
var stdout: *std.io.Writer = undefined;

var stdin_buffer: [IO_BUFFER_SIZE]char = undefined;
var stdin_reader: fs.File.Reader = undefined;
var stdin: *std.io.Reader = undefined;

pub fn init() void {
    stderr_writer = fs.File.stderr().writer(&stderr_buffer);
    stderr = &stderr_writer.interface;
    stdout_writer = fs.File.stdout().writer(&stdout_buffer);
    stdout = &stdout_writer.interface;
    stdin_reader = fs.File.stdin().reader(&stdin_buffer);
    stdin = &stdin_reader.interface;
}

pub fn main() !void {
    init();
    var arenaAlloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arenaAlloc.deinit();
    const alloc = arenaAlloc.allocator();

    const args = try arguments.allocList(alloc);
    switch (args.items.len) {
        0, 1 => {
            try stdout.print(helpMessage ++ "\n", .{});
            try stdout.flush();
            return;
        },
        2 => {},
        else => {
            try printerr("Too many arguments ({d}), expected 1", .{args.items.len - 1});
            try stdout.print(usageMessage ++ "\n", .{});
            try stdout.flush();
            return;
        }
    }

    const projectPath = args.items[1];
    prints(projectPath);
}
