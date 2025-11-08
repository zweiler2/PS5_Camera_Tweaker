const std = @import("std");

const EXPECTED_FIRMWARE_FILE_SIZE = 68_948;

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
const AUTO_EXPOSURE_VALUE_ON = 2;
const AUTO_EXPOSURE_VALUE_OFF = 4;
const BRIGHTNESS_OFFSET = 0x0102BF;
const CONTRAST_OFFSET = 0x0102E3;
const SATURATION_OFFSET = 0x01032B;
const GAIN_OFFSET = 0x0103BB;
const SHARPNESS_OFFSET = 0x01034F;

const Settings = struct {
    discord_fix: bool,
    auto_exposure: bool,
    brightness: u4,
    contrast: u4,
    saturation: u4,
    gain: u4,
    sharpness: u4,
};

const IOStreams = struct {
    stdin: *std.io.Reader,
    stdout: *std.io.Writer,
    stderr: *std.io.Writer,
};

pub fn main() !void {
    // Create an allocator
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator: std.mem.Allocator = arena.allocator();

    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader: std.fs.File.Reader = std.fs.File.stdin().reader(&stdin_buffer);
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.fs.File.Writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.fs.File.Writer = std.fs.File.stderr().writer(&stderr_buffer);

    const io_streams: IOStreams = .{
        .stdin = &stdin_reader.interface,
        .stdout = &stdout_writer.interface,
        .stderr = &stderr_writer.interface,
    };

    // Get arguments with proper cross-platform support
    var args: std.process.ArgIterator = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name but store it for error message
    const prog_name: [:0]const u8 = args.next() orelse return error.NoProgramName;

    // Get firmware path argument
    const firmware_path: [:0]const u8 = args.next() orelse {
        try io_streams.stderr.print(
            \\Please provide a firmware file path!
            \\Usage: {s} <path{c}to{c}firmware_file.bin>
            \\
        , .{ prog_name, std.fs.path.sep, std.fs.path.sep });
        try io_streams.stderr.flush();
        std.process.exit(1);
    };

    const buffer: []u8 = blk: {
        const old_file: std.fs.File = try std.fs.cwd().openFile(firmware_path, .{});
        defer old_file.close();

        const file_size: u64 = try old_file.getEndPos();
        if (file_size != EXPECTED_FIRMWARE_FILE_SIZE) {
            try io_streams.stderr.print(
                \\The firmware file size is incorrect!
                \\It should be: {d} bytes.
                \\But it is:    {d} bytes.
                \\Please provide a valid firmware file.
                \\
            , .{ EXPECTED_FIRMWARE_FILE_SIZE, file_size });
            try io_streams.stderr.flush();
            std.process.exit(1);
        }
        var reader_buffer: [1024]u8 = undefined;
        var old_file_reader: std.fs.File.Reader = old_file.reader(&reader_buffer);
        const old_file_reader_interface: *std.Io.Reader = &old_file_reader.interface;

        break :blk try old_file_reader_interface.readAlloc(allocator, file_size);
    };
    defer allocator.free(buffer);

    try io_streams.stdout.print("Old Firmware Settings:\n", .{});
    try io_streams.stdout.print("  Discord Fix: {}\n", .{buffer[DISCORD_FIX_OFFSETS[0]] == DISCORD_FIX_VALUES[0]});
    try io_streams.stdout.print("  Auto Exposure: {}\n", .{buffer[AUTO_EXPOSURE_OFFSET] == AUTO_EXPOSURE_VALUE_ON});
    try io_streams.stdout.print("  Brightness: {}\n", .{buffer[BRIGHTNESS_OFFSET]});
    try io_streams.stdout.print("  Contrast: {}\n", .{buffer[CONTRAST_OFFSET]});
    try io_streams.stdout.print("  Saturation: {}\n", .{buffer[SATURATION_OFFSET]});
    try io_streams.stdout.print("  Gain: {}\n", .{buffer[GAIN_OFFSET]});
    try io_streams.stdout.print("  Sharpness: {}\n", .{buffer[SHARPNESS_OFFSET]});

    try io_streams.stdout.print("\nNew Firmware Settings:\n", .{});
    editFirmware(buffer, Settings{
        .discord_fix = try readUserInput(bool, "Discord Fix (y/n): ", io_streams),
        .auto_exposure = try readUserInput(bool, "Auto Exposure (y/n): ", io_streams),
        .brightness = try readUserInput(u4, "Brightness (0-8): ", io_streams),
        .contrast = try readUserInput(u4, "Contrast (0-8): ", io_streams),
        .saturation = try readUserInput(u4, "Saturation (0-8): ", io_streams),
        .gain = try readUserInput(u4, "Gain (0-8): ", io_streams),
        .sharpness = try readUserInput(u4, "Sharpness (0-8): ", io_streams),
    });

    var new_firmware_file: std.fs.File = try std.fs.cwd().createFile("output.bin", .{});
    defer new_firmware_file.close();

    var writer_buffer: [1024]u8 = undefined;
    var new_file_writer: std.fs.File.Writer = new_firmware_file.writer(&writer_buffer);
    const new_file_writer_interface: *std.Io.Writer = &new_file_writer.interface;
    try new_file_writer_interface.writeAll(buffer);
}

fn readUserInput(comptime T: type, text: []const u8, io_streams: IOStreams) !T {
    while (true) {
        try io_streams.stdout.print("  {s}", .{text});
        try io_streams.stdout.flush();

        const line_slice: []u8 = io_streams.stdin.takeDelimiterInclusive('\n') catch |err| {
            try io_streams.stderr.print("Error reading input: {}\n", .{err});
            try io_streams.stderr.flush();
            std.process.exit(1);
        };

        const trimmed: []const u8 = std.mem.trim(u8, line_slice, " \t\r\n");

        if (trimmed.len == 0) {
            try io_streams.stderr.print("No input provided! Please try again.\n", .{});
            try io_streams.stderr.flush();
            continue;
        }

        const first_char: u8 = trimmed[0];
        if (T == bool) {
            if (first_char == 'y' or first_char == 'Y') {
                return true;
            } else if (first_char == 'n' or first_char == 'N') {
                return false;
            } else {
                try io_streams.stderr.print("Invalid input: expected 'y' or 'n'! Please try again.\n", .{});
                try io_streams.stderr.flush();
                continue;
            }
        } else if (T == u4) {
            const value: u4 = std.fmt.parseUnsigned(u4, trimmed, 10) catch {
                try io_streams.stderr.print("Invalid input: expected '0'-'8'! Please try again.\n", .{});
                try io_streams.stderr.flush();
                continue;
            };
            if (value <= 8) {
                return value;
            } else {
                try io_streams.stderr.print("Invalid input: expected '0'-'8'! Please try again.\n", .{});
                try io_streams.stderr.flush();
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
    buffer[AUTO_EXPOSURE_OFFSET] = if (settings.auto_exposure) AUTO_EXPOSURE_VALUE_ON else AUTO_EXPOSURE_VALUE_OFF;
    buffer[AUTO_EXPOSURE_OFFSET_2] = if (settings.auto_exposure) AUTO_EXPOSURE_VALUE_ON else AUTO_EXPOSURE_VALUE_OFF;
    buffer[BRIGHTNESS_OFFSET] = settings.brightness;
    buffer[CONTRAST_OFFSET] = settings.contrast;
    buffer[SATURATION_OFFSET] = settings.saturation;
    buffer[GAIN_OFFSET] = settings.gain;
    buffer[SHARPNESS_OFFSET] = settings.sharpness;
}
