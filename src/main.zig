const std = @import("std");

const DISCORD_FIX_OFFSETS = [_]comptime_int{
    0xEEB6, 0xEEB7, 0xEEB8,
    0xEEBB, 0xEEBC, 0xEEBD,
};
const DISCORD_FIX_VALUES = [_]comptime_int{
    21, 22, 5,
    20, 22, 5,
};

const AUTO_EXPOSURE_OFFSET = 0x010403;
const AUTO_EXPOSURE_OFFSET_2 = 0x010407;
const CONTRAST_OFFSET = 0x0102E3;
const SATURATION_OFFSET = 0x01032B;
const GAIN_OFFSET = 0x0103BB;
const SHARPNESS_OFFSET = 0x01034F;

const Settings = struct {
    discord_fix: bool,
    auto_exposure: bool,
    contrast: u4,
    saturation: u4,
    gain: u4,
    sharpness: u4,
};

pub fn main() !void {
    // Create an allocator
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator: std.mem.Allocator = arena.allocator();

    // Get arguments with proper cross-platform support
    var args: std.process.ArgIterator = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name but store it for error message
    const prog_name: [:0]const u8 = args.next() orelse return error.NoProgramName;

    // Get firmware path argument
    const firmware_path: [:0]const u8 = args.next() orelse {
        std.log.err(
            \\Please provide a firmware file path.
            \\
            \\Usage:
            \\  {s} <path{c}to{c}firmware_file.bin>
        , .{ prog_name, std.fs.path.sep, std.fs.path.sep });
        std.process.exit(1);
    };

    const old_firmware_file: std.fs.File = try std.fs.cwd().openFile(firmware_path, .{});
    defer old_firmware_file.close();

    // Read the entire file into memory
    const file_size: u64 = try old_firmware_file.getEndPos();
    const buffer: []u8 = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);
    _ = try old_firmware_file.readAll(buffer);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Old Firmware Settings:\n", .{});
    try stdout.print("  Discord Fix: {}\n", .{buffer[DISCORD_FIX_OFFSETS[0]] == DISCORD_FIX_VALUES[0]});
    try stdout.print("  Auto Exposure: {}\n", .{buffer[AUTO_EXPOSURE_OFFSET] == 2});
    try stdout.print("  Contrast: {}\n", .{buffer[CONTRAST_OFFSET]});
    try stdout.print("  Saturation: {}\n", .{buffer[SATURATION_OFFSET]});
    try stdout.print("  Gain: {}\n", .{buffer[GAIN_OFFSET]});
    try stdout.print("  Sharpness: {}\n", .{buffer[SHARPNESS_OFFSET]});

    try stdout.print("\nNew Firmware Settings:\n", .{});
    editFirmware(buffer, Settings{
        .discord_fix = readUserInput(bool, "Discord Fix (y/n): "),
        .auto_exposure = readUserInput(bool, "Auto Exposure (y/n): "),
        .contrast = readUserInput(u4, "Contrast (0-8): "),
        .saturation = readUserInput(u4, "Saturation (0-8): "),
        .gain = readUserInput(u4, "Gain (0-8): "),
        .sharpness = readUserInput(u4, "Sharpness (0-8): "),
    });

    var new_firmware_file: std.fs.File = try std.fs.cwd().createFile("output.bin", .{});
    defer new_firmware_file.close();
    try new_firmware_file.writeAll(buffer);
}

fn readUserInput(comptime T: type, text: []const u8) T {
    var buffer: [8]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    while (true) {
        stdout.print("  {s}", .{text}) catch {
            std.log.err("Error printing to stdout", .{});
        };

        const line_slice: []u8 = stdin.readUntilDelimiter(&buffer, '\n') catch |err| {
            std.log.err("Error reading input: {}", .{err});
            std.process.exit(1);
        };

        const trimmed: []const u8 = std.mem.trim(u8, line_slice, " \r\n");

        if (trimmed.len == 0) {
            std.log.err("No input provided", .{});
            continue;
        }

        const first_char: u8 = trimmed[0];
        if (T == bool) {
            if (first_char == 'y' or first_char == 'Y') {
                return true;
            } else if (first_char == 'n' or first_char == 'N') {
                return false;
            } else {
                std.log.err("Invalid input: expected 'y' or 'n'", .{});
                continue;
            }
        } else if (T == u4) {
            const value: u4 = std.fmt.parseInt(u4, trimmed, 10) catch {
                std.log.err("Invalid input: expected '0'-'8'", .{});
                continue;
            };
            if (value <= 8) {
                return value;
            } else {
                std.log.err("Invalid input: expected '0'-'8'", .{});
                continue;
            }
        }
    }
}

fn editFirmware(buffer: []u8, settings: Settings) void {
    if (settings.discord_fix) {
        inline for (DISCORD_FIX_OFFSETS, DISCORD_FIX_VALUES) |offset, value| {
            buffer[offset] = value;
        }
    }
    buffer[AUTO_EXPOSURE_OFFSET] = if (settings.auto_exposure) 2 else 4;
    buffer[AUTO_EXPOSURE_OFFSET_2] = if (settings.auto_exposure) 2 else 4;
    buffer[CONTRAST_OFFSET] = settings.contrast;
    buffer[SATURATION_OFFSET] = settings.saturation;
    buffer[GAIN_OFFSET] = settings.gain;
    buffer[SHARPNESS_OFFSET] = settings.sharpness;
}
