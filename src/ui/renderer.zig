const std = @import("std");
const model = @import("../model.zig");
const widget = @import("widget.zig");

pub const Renderer = struct {
    pub fn renderDashboard(
        snapshot: model.SystemSnapshot,
        writer: anytype,
        width: usize,
        enable_color: bool,
        interval_ms: u64,
        is_paused: bool,
    ) !void {
        // Move cursor home and clear
        try writer.writeAll("\x1b[H\x1b[2J");

        const term_w = @max(60, width);
        const inner_w = term_w - 4;

        // Header Title
        if (enable_color) try writer.writeAll("\x1b[1;36m"); // Cyan Bold
        try writer.print("┌── local-status :: macOS Hardware Monitor ", .{});
        if (enable_color) try writer.writeAll("\x1b[0m");

        const status_text = if (is_paused) "[PAUSED]" else "[LIVE]";
        if (enable_color) {
            if (is_paused) {
                try writer.writeAll("\x1b[33;1m");
            } else {
                try writer.writeAll("\x1b[32;1m");
            }
        }
        try writer.print("{s}", .{status_text});
        if (enable_color) try writer.writeAll("\x1b[0m");

        const rate_info = try std.fmt.allocPrint(std.heap.page_allocator, " ({d}ms) ──┐\n", .{interval_ms});
        defer std.heap.page_allocator.free(rate_info);
        try writer.writeAll(rate_info);

        // ───────────────────────────────
        // 1. CPU SECTION
        // ───────────────────────────────
        try renderBoxTop(writer, "CPU", inner_w, enable_color);

        // CPU Total Line
        try writer.print("│  Model: {s} ({d} cores: {d}P + {d}E)\n", .{
            snapshot.cpu.model_name,
            snapshot.cpu.core_count,
            snapshot.cpu.p_core_count,
            snapshot.cpu.e_core_count,
        });

        try writer.writeAll("│  Total: ");
        const gauge_w = @min(30, inner_w / 3);
        try widget.renderGauge(writer, snapshot.cpu.total_usage, gauge_w, enable_color);
        try writer.print(" {d:>5.1}%  (usr: {d:.1}%, sys: {d:.1}%, idle: {d:.1}%)\n", .{
            snapshot.cpu.total_usage,
            snapshot.cpu.user_percent,
            snapshot.cpu.system_percent,
            snapshot.cpu.idle_percent,
        });

        // Load Avg Line
        try writer.print("│  Load Avg: {d:.2}, {d:.2}, {d:.2}\n", .{
            snapshot.cpu.load_avg[0],
            snapshot.cpu.load_avg[1],
            snapshot.cpu.load_avg[2],
        });

        // Per-Core Grid (2 columns)
        if (snapshot.cpu.cores.len > 0) {
            try writer.writeAll("│  Cores:\n");
            var c_idx: usize = 0;
            while (c_idx < snapshot.cpu.cores.len) {
                try writer.writeAll("│   ");
                // Column 1
                const c1 = snapshot.cpu.cores[c_idx];
                const type_str1 = if (c1.is_performance) "P" else "E";
                try writer.print("C{d:>2} ({s}): ", .{ c1.core_id + 1, type_str1 });
                try widget.renderGauge(writer, c1.usage_percent, 10, enable_color);
                try writer.print(" {d:>4.0}%", .{c1.usage_percent});

                // Column 2
                if (c_idx + 1 < snapshot.cpu.cores.len) {
                    const c2 = snapshot.cpu.cores[c_idx + 1];
                    const type_str2 = if (c2.is_performance) "P" else "E";
                    try writer.print("   C{d:>2} ({s}): ", .{ c2.core_id + 1, type_str2 });
                    try widget.renderGauge(writer, c2.usage_percent, 10, enable_color);
                    try writer.print(" {d:>4.0}%", .{c2.usage_percent});
                }
                try writer.writeAll("\n");
                c_idx += 2;
            }
        }
        try renderBoxBottom(writer, inner_w);

        // ───────────────────────────────
        // 2. GPU SECTION
        // ───────────────────────────────
        try renderBoxTop(writer, "GPU (Apple Silicon)", inner_w, enable_color);
        try writer.print("│  Model: {s}\n", .{snapshot.gpu.model_name});
        try writer.writeAll("│  Usage: ");
        try widget.renderGauge(writer, snapshot.gpu.utilization_percent, gauge_w, enable_color);
        try writer.print(" {d:>5.1}%\n", .{snapshot.gpu.utilization_percent});
        try renderBoxBottom(writer, inner_w);

        // ───────────────────────────────
        // 3. MEMORY SECTION
        // ───────────────────────────────
        try renderBoxTop(writer, "Memory (RAM & Swap)", inner_w, enable_color);

        var buf_tot: [32]u8 = undefined;
        var buf_used: [32]u8 = undefined;
        var buf_free: [32]u8 = undefined;
        var buf_act: [32]u8 = undefined;
        var buf_wired: [32]u8 = undefined;
        var buf_comp: [32]u8 = undefined;

        const tot_str = widget.formatBytes(snapshot.memory.total_bytes, &buf_tot);
        const used_str = widget.formatBytes(snapshot.memory.used_bytes, &buf_used);
        const free_str = widget.formatBytes(snapshot.memory.free_bytes, &buf_free);
        const act_str = widget.formatBytes(snapshot.memory.active_bytes, &buf_act);
        const wired_str = widget.formatBytes(snapshot.memory.wired_bytes, &buf_wired);
        const comp_str = widget.formatBytes(snapshot.memory.compressed_bytes, &buf_comp);

        try writer.writeAll("│  RAM:  ");
        try widget.renderGauge(writer, snapshot.memory.usage_percent, gauge_w, enable_color);
        try writer.print(" {d:>5.1}%  ({s} / {s}, free: {s})\n", .{
            snapshot.memory.usage_percent,
            used_str,
            tot_str,
            free_str,
        });

        try writer.print("│         App: {s}  Wired: {s}  Compressed: {s}\n", .{
            act_str,
            wired_str,
            comp_str,
        });

        // Swap line
        var buf_sw_tot: [32]u8 = undefined;
        var buf_sw_used: [32]u8 = undefined;
        const sw_tot_str = widget.formatBytes(snapshot.memory.swap_total_bytes, &buf_sw_tot);
        const sw_used_str = widget.formatBytes(snapshot.memory.swap_used_bytes, &buf_sw_used);

        try writer.writeAll("│  Swap: ");
        try widget.renderGauge(writer, snapshot.memory.swap_percent, gauge_w, enable_color);
        try writer.print(" {d:>5.1}%  ({s} / {s})\n", .{
            snapshot.memory.swap_percent,
            sw_used_str,
            sw_tot_str,
        });
        try renderBoxBottom(writer, inner_w);

        // ───────────────────────────────
        // 4. DISK SECTION
        // ───────────────────────────────
        try renderBoxTop(writer, "Storage (Disk Volumes)", inner_w, enable_color);
        for (snapshot.disks) |disk| {
            var b_d_tot: [32]u8 = undefined;
            var b_d_used: [32]u8 = undefined;
            var b_d_free: [32]u8 = undefined;
            const d_tot_str = widget.formatBytes(disk.total_bytes, &b_d_tot);
            const d_used_str = widget.formatBytes(disk.used_bytes, &b_d_used);
            const d_free_str = widget.formatBytes(disk.free_bytes, &b_d_free);

            try writer.print("│  {s:<28} ", .{disk.mount_point});
            try widget.renderGauge(writer, disk.usage_percent, 20, enable_color);
            try writer.print(" {d:>4.0}% ({s} / {s}, free: {s})\n", .{
                disk.usage_percent,
                d_used_str,
                d_tot_str,
                d_free_str,
            });
        }
        try renderBoxBottom(writer, inner_w);

        // ───────────────────────────────
        // 5. FOOTER & CONTROLS
        // ───────────────────────────────
        if (enable_color) try writer.writeAll("\x1b[90m");
        try writer.writeAll("  [q] Quit   [p] Pause/Resume   [+/-] Speed   [r] Refresh   [h] Help\n");
        if (enable_color) try writer.writeAll("\x1b[0m");
    }

    pub fn renderSnapshotOnce(snapshot: model.SystemSnapshot, writer: anytype, enable_color: bool) !void {
        if (enable_color) try writer.writeAll("\x1b[1;36m");
        try writer.print("=== local-status :: macOS System Status ===\n", .{});
        if (enable_color) try writer.writeAll("\x1b[0m");

        // CPU
        try writer.print("CPU:  {s} ({d} cores)\n", .{ snapshot.cpu.model_name, snapshot.cpu.core_count });
        try writer.writeAll("      Total Load: ");
        try widget.renderGauge(writer, snapshot.cpu.total_usage, 20, enable_color);
        try writer.print(" {d:.1}% (usr: {d:.1}%, sys: {d:.1}%, idle: {d:.1}%)\n", .{
            snapshot.cpu.total_usage,
            snapshot.cpu.user_percent,
            snapshot.cpu.system_percent,
            snapshot.cpu.idle_percent,
        });
        try writer.print("      Load Avg:   {d:.2}, {d:.2}, {d:.2}\n\n", .{
            snapshot.cpu.load_avg[0],
            snapshot.cpu.load_avg[1],
            snapshot.cpu.load_avg[2],
        });

        // GPU
        try writer.print("GPU:  {s}\n", .{snapshot.gpu.model_name});
        try writer.writeAll("      Usage:      ");
        try widget.renderGauge(writer, snapshot.gpu.utilization_percent, 20, enable_color);
        try writer.print(" {d:.1}%\n\n", .{snapshot.gpu.utilization_percent});

        // Memory
        var b1: [32]u8 = undefined;
        var b2: [32]u8 = undefined;
        var b3: [32]u8 = undefined;
        try writer.writeAll("RAM:  Usage:      ");
        try widget.renderGauge(writer, snapshot.memory.usage_percent, 20, enable_color);
        try writer.print(" {d:.1}% ({s} / {s}, free: {s})\n", .{
            snapshot.memory.usage_percent,
            widget.formatBytes(snapshot.memory.used_bytes, &b1),
            widget.formatBytes(snapshot.memory.total_bytes, &b2),
            widget.formatBytes(snapshot.memory.free_bytes, &b3),
        });

        var b4: [32]u8 = undefined;
        var b5: [32]u8 = undefined;
        try writer.writeAll("Swap: Usage:      ");
        try widget.renderGauge(writer, snapshot.memory.swap_percent, 20, enable_color);
        try writer.print(" {d:.1}% ({s} / {s})\n\n", .{
            snapshot.memory.swap_percent,
            widget.formatBytes(snapshot.memory.swap_used_bytes, &b4),
            widget.formatBytes(snapshot.memory.swap_total_bytes, &b5),
        });

        // Disks
        try writer.writeAll("Disks:\n");
        for (snapshot.disks) |disk| {
            var bd1: [32]u8 = undefined;
            var bd2: [32]u8 = undefined;
            try writer.print("  - {s:<28} ", .{disk.mount_point});
            try widget.renderGauge(writer, disk.usage_percent, 16, enable_color);
            try writer.print(" {d:>3.0}% ({s} / {s})\n", .{
                disk.usage_percent,
                widget.formatBytes(disk.used_bytes, &bd1),
                widget.formatBytes(disk.total_bytes, &bd2),
            });
        }
    }

    pub fn renderJson(snapshot: model.SystemSnapshot, writer: anytype) !void {
        try writer.writeAll("{\n");
        try writer.print("  \"timestamp\": {d},\n", .{snapshot.timestamp});

        // CPU
        try writer.writeAll("  \"cpu\": {\n");
        try writer.print("    \"model\": \"{s}\",\n", .{snapshot.cpu.model_name});
        try writer.print("    \"total_usage\": {d:.2},\n", .{snapshot.cpu.total_usage});
        try writer.print("    \"user_percent\": {d:.2},\n", .{snapshot.cpu.user_percent});
        try writer.print("    \"system_percent\": {d:.2},\n", .{snapshot.cpu.system_percent});
        try writer.print("    \"idle_percent\": {d:.2},\n", .{snapshot.cpu.idle_percent});
        try writer.print("    \"cores_count\": {d},\n", .{snapshot.cpu.core_count});
        try writer.print("    \"load_avg\": [{d:.2}, {d:.2}, {d:.2}]\n", .{
            snapshot.cpu.load_avg[0],
            snapshot.cpu.load_avg[1],
            snapshot.cpu.load_avg[2],
        });
        try writer.writeAll("  },\n");

        // GPU
        try writer.writeAll("  \"gpu\": {\n");
        try writer.print("    \"model\": \"{s}\",\n", .{snapshot.gpu.model_name});
        try writer.print("    \"utilization_percent\": {d:.2}\n", .{snapshot.gpu.utilization_percent});
        try writer.writeAll("  },\n");

        // Memory
        try writer.writeAll("  \"memory\": {\n");
        try writer.print("    \"total_bytes\": {d},\n", .{snapshot.memory.total_bytes});
        try writer.print("    \"used_bytes\": {d},\n", .{snapshot.memory.used_bytes});
        try writer.print("    \"free_bytes\": {d},\n", .{snapshot.memory.free_bytes});
        try writer.print("    \"active_bytes\": {d},\n", .{snapshot.memory.active_bytes});
        try writer.print("    \"wired_bytes\": {d},\n", .{snapshot.memory.wired_bytes});
        try writer.print("    \"compressed_bytes\": {d},\n", .{snapshot.memory.compressed_bytes});
        try writer.print("    \"swap_total_bytes\": {d},\n", .{snapshot.memory.swap_total_bytes});
        try writer.print("    \"swap_used_bytes\": {d},\n", .{snapshot.memory.swap_used_bytes});
        try writer.print("    \"usage_percent\": {d:.2}\n", .{snapshot.memory.usage_percent});
        try writer.writeAll("  },\n");

        // Disks
        try writer.writeAll("  \"disks\": [\n");
        for (snapshot.disks, 0..) |disk, i| {
            try writer.writeAll("    {\n");
            try writer.print("      \"mount_point\": \"{s}\",\n", .{disk.mount_point});
            try writer.print("      \"total_bytes\": {d},\n", .{disk.total_bytes});
            try writer.print("      \"used_bytes\": {d},\n", .{disk.used_bytes});
            try writer.print("      \"free_bytes\": {d},\n", .{disk.free_bytes});
            try writer.print("      \"usage_percent\": {d:.2}\n", .{disk.usage_percent});
            if (i + 1 < snapshot.disks.len) {
                try writer.writeAll("    },\n");
            } else {
                try writer.writeAll("    }\n");
            }
        }
        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");
    }

    fn renderBoxTop(writer: anytype, title: []const u8, width: usize, enable_color: bool) !void {
        if (enable_color) try writer.writeAll("\x1b[36m");
        try writer.print("┌─ {s} ", .{title});
        const title_len = title.len + 4;
        const rest = if (width > title_len) width - title_len else 0;
        for (0..rest) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┐\n");
        if (enable_color) try writer.writeAll("\x1b[0m");
    }

    fn renderBoxBottom(writer: anytype, width: usize) !void {
        try writer.writeAll("└");
        for (0..width) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┘\n");
    }
};
