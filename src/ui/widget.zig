const std = @import("std");

pub fn formatBytes(bytes: u64, buf: []u8) []const u8 {
    const f_bytes = @as(f64, @floatFromInt(bytes));
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
        return std.fmt.bufPrint(buf, "{d:.2} TB", .{f_bytes / (1024.0 * 1024.0 * 1024.0 * 1024.0)}) catch "0 B";
    } else if (bytes >= 1024 * 1024 * 1024) {
        return std.fmt.bufPrint(buf, "{d:.2} GB", .{f_bytes / (1024.0 * 1024.0 * 1024.0)}) catch "0 B";
    } else if (bytes >= 1024 * 1024) {
        return std.fmt.bufPrint(buf, "{d:.1} MB", .{f_bytes / (1024.0 * 1024.0)}) catch "0 B";
    } else if (bytes >= 1024) {
        return std.fmt.bufPrint(buf, "{d:.0} KB", .{f_bytes / 1024.0}) catch "0 B";
    } else {
        return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch "0 B";
    }
}

pub fn renderGauge(writer: anytype, percent: f32, width: usize, enable_color: bool) !void {
    if (width == 0) return;
    const clamped = @max(0.0, @min(100.0, percent));
    const filled_chars: usize = @intFromFloat(@as(f32, @floatFromInt(width)) * clamped / 100.0);
    const empty_chars = width - filled_chars;

    if (enable_color) {
        if (clamped > 85.0) {
            try writer.writeAll("\x1b[31;1m"); // Red bold
        } else if (clamped > 60.0) {
            try writer.writeAll("\x1b[33;1m"); // Yellow bold
        } else {
            try writer.writeAll("\x1b[32;1m"); // Green bold
        }
    }

    try writer.writeAll("[");
    for (0..filled_chars) |_| {
        try writer.writeAll("█");
    }
    if (enable_color) {
        try writer.writeAll("\x1b[0m\x1b[90m"); // Dim for empty
    }
    for (0..empty_chars) |_| {
        try writer.writeAll("░");
    }
    if (enable_color) {
        try writer.writeAll("\x1b[0m");
    }
    try writer.writeAll("]");
}
