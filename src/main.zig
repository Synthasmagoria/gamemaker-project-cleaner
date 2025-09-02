const std = @import("std");
const mem = std.mem;
const zpl = @import("zpl.zig");
const fs = std.fs;
const c = @import("c.zig").c;
const Allocator = std.mem.Allocator;

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

fn handleCouldntAccessError(err: fs.Dir.AccessError, writer: *std.Io.Writer) !void {
    switch (err) {
        error.AccessDenied => try printerr("Access denied", .{}),
        error.NameTooLong => try printerr("Name too long", .{}),
        error.BadPathName => try printerr("Bad path name", .{}),
        else => try printerr("Couldn't access path", .{}),
    }
    try writer.flush();
}

const PathType = enum {
    File,
    Directory,
    Unknown
};
fn pathGetTypeAbs(path: []const char) !PathType {
    const dirNull = fs.openDirAbsolute(path, .{}) catch blk: {
        break :blk null;
    };
    if (dirNull) |dir| {
        @constCast(&dir).close();
        return .Directory;
    }

    const fNull = fs.openFileAbsolute(path, .{}) catch blk: {
        break :blk null;
    };
    if (fNull) |f| {
        f.close();
        return .File;
    }

    return .Unknown;
}

fn pathGetTypeCwd(path: []const char) !PathType {
    const dirNull = fs.cwd().openDir(path, .{}) catch blk: {
        break :blk null;
    };
    if (dirNull) |dir| {
        @constCast(&dir).close();
        return .Directory;
    }

    const fNull = fs.cwd().openFile(path, .{}) catch blk: {
        break :blk null;
    };
    if (fNull) |f| {
        f.close();
        return .File;
    }

    return .Unknown;
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

pub fn allocArgsList(alloc: Allocator) !std.ArrayList([]u8) {
    var args = try std.process.argsWithAllocator(alloc);
    var arg_list = try std.ArrayList([]u8).initCapacity(alloc, 10);
    while (args.next()) |arg| {
        try arg_list.append(alloc, try alloc.dupe(u8, arg));
    }
    return arg_list;
}

const OpenProjectDirectoryError = error{
    NoDirnameAbs,
    UnknownAbs,
    NoDirname,
    Unknown
};
pub fn openProjectDirectory(path: []const char) !fs.Dir {
    if (fs.path.isAbsolute(path)) {
        switch (try pathGetTypeAbs(path)) {
            .Directory => {
                return try fs.openDirAbsolute(path, .{.access_sub_paths = true, .iterate = true});
            },
            .File => {
                if (fs.path.dirname(path)) |dirname| {
                    return try fs.openDirAbsolute(dirname, .{.access_sub_paths = true, .iterate = true});
                } else {
                    return OpenProjectDirectoryError.NoDirnameAbs;
                }
            },
            .Unknown => {
                try printerr("Path points to unknown file type", .{});
                return OpenProjectDirectoryError.UnknownAbs;
            }
        }
    } else {
        switch (try pathGetTypeCwd(path)) {
            .Directory => {
                return try fs.cwd().openDir(path, .{.access_sub_paths = true, .iterate = true});
            },
            .File => {
                if (fs.path.dirname(path)) |dirname| {
                    return try fs.cwd().openDir(dirname, .{.access_sub_paths = true, .iterate = true});
                } else {
                    try printerr("Couldn't get project directory from path", .{});
                    return OpenProjectDirectoryError.NoDirname;
                }
            },
            .Unknown => {
                try printerr("Path points to unknown file type", .{});
                return OpenProjectDirectoryError.Unknown;
            }
        }
    }
}

pub fn main() !void {
    init();
    var arenaAlloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arenaAlloc.deinit();
    const alloc = arenaAlloc.allocator();

    const args = try allocArgsList(alloc);
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


    if (projectPath.len == 0) {
        try printerr("Passed path was empty", .{});
        try stdout.print(usageMessage ++ "\n", .{});
        try stdout.flush();
        return;
    }

    if (fs.path.isAbsolute(projectPath)) {
        fs.accessAbsolute(projectPath, .{}) catch |err| {
            try handleCouldntAccessError(err, stderr);
            return;
        };
    } else {
        fs.cwd().access(projectPath, .{}) catch |err| {
            try handleCouldntAccessError(err, stderr);
            return;
        };
    }

    var wd = openProjectDirectory(projectPath) catch |err| {
        switch (err) {
            OpenProjectDirectoryError.NoDirname,
            OpenProjectDirectoryError.NoDirnameAbs => {
                try printerr("Couldn't get project directory from path", .{});
                return;
            },
            OpenProjectDirectoryError.Unknown,
            OpenProjectDirectoryError.UnknownAbs => {
                try printerr("Path points to unknown file/directory type", .{});
                return;
            },
            else => {
                try printerr("Something went wrong while opening the project path", .{});
                return;
            }
        }
    };
    defer wd.close();

    prints(projectPath);
}
