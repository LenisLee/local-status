const std = @import("std");

pub const model = @import("model.zig");
pub const config = @import("config.zig");
pub const time_util = @import("time_util.zig");
pub const cpu = @import("monitor/cpu.zig");
pub const memory = @import("monitor/memory.zig");
pub const disk = @import("monitor/disk.zig");
pub const gpu = @import("monitor/gpu.zig");
pub const collector = @import("monitor/collector.zig");
pub const widget = @import("ui/widget.zig");
pub const terminal = @import("ui/terminal.zig");
pub const renderer = @import("ui/renderer.zig");

test "formatBytes formatting test" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("500 B", widget.formatBytes(500, &buf));
    try std.testing.expectEqualStrings("1 KB", widget.formatBytes(1024, &buf));
    try std.testing.expectEqualStrings("1.0 MB", widget.formatBytes(1024 * 1024, &buf));
    try std.testing.expectEqualStrings("1.00 GB", widget.formatBytes(1024 * 1024 * 1024, &buf));
    try std.testing.expectEqualStrings("16.00 GB", widget.formatBytes(16 * 1024 * 1024 * 1024, &buf));
}

test "config argument parsing test" {
    const args = [_][]const u8{ "local-status", "--once", "-i", "500", "--no-color" };
    const cfg = config.Config.parse(&args);
    try std.testing.expect(cfg.once == true);
    try std.testing.expect(cfg.interval_ms == 500);
    try std.testing.expect(cfg.no_color == true);
    try std.testing.expect(cfg.json == false);
}

test "renderGauge test" {
    const TestWriter = struct {
        buf: [128]u8 = undefined,
        len: usize = 0,
        pub fn writeAll(self: *@This(), bytes: []const u8) !void {
            @memcpy(self.buf[self.len .. self.len + bytes.len], bytes);
            self.len += bytes.len;
        }
    };
    var tw = TestWriter{};
    try widget.renderGauge(&tw, 50.0, 10, false);
    const result = tw.buf[0..tw.len];
    try std.testing.expect(std.mem.startsWith(u8, result, "["));
    try std.testing.expect(std.mem.endsWith(u8, result, "]"));
}

test "collector hardware sample test" {
    var coll = collector.SystemCollector.init();
    defer coll.deinit();

    const snapshot = coll.sample();
    try std.testing.expect(snapshot.cpu.core_count > 0);
    try std.testing.expect(snapshot.memory.total_bytes > 0);
    try std.testing.expect(snapshot.disks.len > 0);
}
