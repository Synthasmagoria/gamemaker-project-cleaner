const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const zpl = @import("zpl.zig");
const fs = std.fs;
const c = @import("c.zig").c;
const Allocator = std.mem.Allocator;

const char = u8;

fn prints(str: anytype) void {
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

fn pathTruncateExtension(path: []const char) []const char {
    return path[0..path.len - fs.path.extension(path).len];
}

fn stringContainsOnly(haystack: []const char, needles: []const char) bool {
    for (haystack) |straw| {
        if (!std.mem.containsAtLeast(u8, needles, 1, &.{straw})) {
            return false;
        }
    }
    return true;
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

fn stringLower(str: []char) void {
    var i: usize = 0;
    while (i < str.len) : (i += 1) {
        if (str[i] >= 'A' and str[i] <= 'Z') {
            str[i] += 'a' - 'A';
        }
    }
}

test stringLower {
    var str = "HeLLO, I'm ///// kinda CaPITALIZed".*;
    stringLower(@constCast(&str));
    try std.testing.expectEqual("hello, i'm ///// kinda capitalized".*, str);
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
    Unknown,
    NotYyp,
};
const OpenProjectDirectoryResult = struct {
    directoryPath: []const char,
    projectFileName: []const char,
    pathWasFilepath: bool,
};
pub fn getProjectDirectory(alloc: Allocator, path: []const char) !OpenProjectDirectoryResult {
    if (fs.path.isAbsolute(path)) {
        switch (try pathGetTypeAbs(path)) {
            .Directory => {
                return .{
                    .projectFileName = try directoryFindProjectFilename(alloc, path),
                    .directoryPath = path,
                    .pathWasFilepath = false};
            },
            .File => {
                if (!mem.eql(u8, fs.path.extension(path), ".yyp")) {
                    return OpenProjectDirectoryError.NotYyp;
                }
                if (fs.path.dirname(path)) |dirname| {
                    return .{
                        .projectFileName = fs.path.basename(path),
                        .directoryPath = dirname,
                        .pathWasFilepath = true};
                } else {
                    return OpenProjectDirectoryError.NoDirnameAbs;
                }
            },
            .Unknown => {
                return OpenProjectDirectoryError.UnknownAbs;
            }
        }
    } else {
        switch (try pathGetTypeCwd(path)) {
            .Directory => {
                return .{
                    .projectFileName = try directoryFindProjectFilename(alloc, path),
                    .directoryPath = path,
                    .pathWasFilepath = false};
            },
            .File => {
                if (!mem.eql(u8, fs.path.extension(path), ".yyp")) {
                    return OpenProjectDirectoryError.NotYyp;
                }
                if (fs.path.dirname(path)) |dirname| {
                    return .{
                        .projectFileName = fs.path.basename(path),
                        .directoryPath = dirname,
                        .pathWasFilepath = true};
                } else {
                    return OpenProjectDirectoryError.NoDirname;
                }
            },
            .Unknown => {
                return OpenProjectDirectoryError.Unknown;
            }
        }
    }
}

fn directoryFindProjectFilename(alloc: Allocator, path: []const char) ![]const u8 {
    var dir = try openDirRelOrAbs(path, .{.iterate = true, .access_sub_paths = false});
    defer dir.close();
    var walker = try dir.walk(alloc);
    while (try walker.next()) |item| {
        if (mem.eql(u8, fs.path.extension(item.basename), ".yyp")) {
            return alloc.dupe(u8, item.basename);
        }
    }
    return error.CouldntFindProjectFile;
}

fn openDirRelOrAbs(path: []const char, flags: fs.Dir.OpenOptions) !fs.Dir {
    if (fs.path.isAbsolute(path)) {
        return try fs.openDirAbsolute(path, flags);
    } else {
        return try fs.cwd().openDir(path, flags);
    }
}

fn openFileRelOrAbs(path: []const char, flags: fs.File.OpenFlags) !fs.File {
    if (fs.path.isAbsolute(path)) {
        return try fs.openFileAbsolute(path, flags);
    } else {
        return try fs.cwd().openFile(path, flags);
    }
}

fn openFileRelOrAbsReadToEndAllocDir(dir: fs.Dir, alloc: Allocator, path: []const char) ![:0]const u8 {
    const f = try dir.openFile(path, .{});
    defer f.close();
    return f.readToEndAllocOptions(alloc, std.math.maxInt(usize), null, .of(u8), 0);
}

pub fn main() !void {
    init();
    runProgram() catch |err| {
        switch (err) {
            error.OutOfMemory => {
                try printerr("Out of memory", .{});
                return;
            },
            else => {
                return err;
            },
        }
    };
}

pub fn runProgram() !void {
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

    const openProjectDirectoryResult = getProjectDirectory(alloc, projectPath) catch |err| {
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
            OpenProjectDirectoryError.NotYyp => {
                try printerr("File pointed to by path was not a yyp", .{});
                return;
            },
            else => {
                std.debug.print("{any}\n", .{err});
                try printerr("Something went wrong while opening the project path", .{});
                return;
            }
        }
    };

    const projDir = try openDirRelOrAbs(openProjectDirectoryResult.directoryPath, .{.iterate = true, .access_sub_paths = true});
    const projectJson5 = try openFileRelOrAbsReadToEndAllocDir(projDir, alloc, openProjectDirectoryResult.projectFileName);
    var root = std.mem.zeroes(zpl.AdtNode);
    const zpl_alloc = c.zpl_heap_allocator();
    switch (c.zpl_json_parse(@ptrCast(&root), @ptrCast(@constCast(projectJson5.ptr)), zpl_alloc)) {
        c.ZPL_JSON_ERROR_NONE => {},
        else => {
            try printerr("Failed to parse json5 in .yyp", .{});
            return;
        }
    }

    var resourceMap = std.StringHashMapUnmanaged([]const u8).empty;
    if (root.query_type("resources", .Array)) |resourcesNode| {
        const resourcesHeader = resourcesNode.get_array_header();
        for (0..@as(usize, @intCast(resourcesHeader.count))) |i| {
            const resourceNode = resourcesNode.get_array_child(i);
            if (resourceNode.query_type("id/path", .String)) |pathNode| {
                const resourcePath = mem.span(pathNode.data.string);
                if (fs.path.dirname(resourcePath)) |resourceDirname| {
                    const resourceNameLower = try alloc.dupe(u8, fs.path.basename(resourcePath));
                    stringLower(@constCast(resourceNameLower));
                    try resourceMap.put(
                        alloc,
                        try alloc.dupe(u8, resourceDirname),
                        pathTruncateExtension(resourceNameLower));
                }
            }
        }
    } else {
        try printerr("Coldn't find resources array in Gamemaker project file", .{});
        return;
    }

    var iter = resourceMap.iterator();
    var deletionCount: usize = 0;
    var deletionList = try std.ArrayList([]const u8).initCapacity(alloc, 1000);
    while (iter.next()) |resource| {
        const dirName = resource.key_ptr.*;
        const resourceNameLower = resource.value_ptr.*;
        var dir = try projDir.openDir(dirName, .{.access_sub_paths = false, .iterate = true});
        var walker = try dir.walk(alloc);
        while (try walker.next()) |item| {
            const basenameLower = try alloc.dupe(u8, item.basename);
            stringLower(@constCast(basenameLower));
            const basenameLowerNoExt = pathTruncateExtension(basenameLower);
            const extLower = fs.path.extension(basenameLower);
            const resourceNamesMatch = mem.eql(u8, basenameLowerNoExt, resourceNameLower);
            const isDeletableFileType = mem.eql(u8, extLower, ".png") or mem.eql(u8, extLower, ".yy");
            const isGmImageFileName = stringContainsOnly(basenameLowerNoExt, "abcdef0123456789-") and basenameLowerNoExt.len == 36;
            const isOutputTileset = mem.eql(u8, basenameLowerNoExt, "output_tileset");
            if (item.kind == .file and !resourceNamesMatch and isDeletableFileType and !isGmImageFileName and !isOutputTileset) {
                if (builtin.os.tag == .windows) {
                    const dirnameConverted = try alloc.alloc(u8, dirName.len);
                    _ = std.mem.replace(u8, dirName, &.{fs.path.sep_posix}, &.{fs.path.sep_windows}, dirnameConverted);
                    try deletionList.append(alloc, try fs.path.join(alloc, &.{dirnameConverted, item.basename}));
                } else {
                    try deletionList.append(alloc, try fs.path.join(alloc, &.{dirName, item.basename}));
                }
                deletionCount += 1;
            }
        }
    }

    for (deletionList.items) |item| {
        try printinfo("Would delete '{s}'", .{item});
    }

    try printinfo("Will delete a total of {d} files", .{deletionCount});
    try stdout.print("Continue (y/n):", .{});
    try stdout.flush();

    var input: [1]char = .{0};
    stdin.readSliceAll(&input) catch {
        try printerr("Aborting...", .{});
        return;
    };

    stringLower(&input);
    switch (input[0]) {
        'y' => {},
        'n' => {
            try printinfo("Aborting...", .{});
            return;
        },
        else => {
            try printerr("Invalid input. Aborting...", .{});
            return;
        }
    }

    for (deletionList.items) |item| {
        projDir.deleteFile(item) catch |err| {
            try stderr.print("{any}: '{s}'\n", .{err, item});
            try stderr.flush();
        };
    }
}
