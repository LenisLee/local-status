const std = @import("std");
const local_status = @import("local_status");
const Config = local_status.config.Config;
const SystemCollector = local_status.collector.SystemCollector;
const Renderer = local_status.renderer.Renderer;
const Terminal = local_status.terminal.Terminal;
const StdoutWriter = local_status.terminal.StdoutWriter;
const time_util = local_status.time_util;

pub extern "c" fn signal(sig: c_int, handler: ?*const fn (c_int) callconv(.c) void) ?*const fn (c_int) callconv(.c) void;
pub extern "c" fn exit(status: c_int) noreturn;
pub const SIGINT: c_int = 2;
pub const SIGTERM: c_int = 15;

var global_term: ?*Terminal = null;

fn handleSignal(_: c_int) callconv(.c) void {
    if (global_term) |term| {
        term.restoreMode();
    }
    exit(0);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const cfg = Config.parse(args);

    const sw = StdoutWriter{};

    if (cfg.show_help) {
        try Config.printHelp(sw);
        return;
    }

    if (cfg.show_version) {
        try sw.print("local-status version 0.1.0 (macOS Darwin)\n", .{});
        return;
    }

    var collector = SystemCollector.init();
    defer collector.deinit();

    // Initial sample to warm up CPU and GPU deltas
    _ = collector.sample();

    if (cfg.once or cfg.json) {
        // Sleep 200ms to allow a meaningful delta sample
        time_util.sleepMs(200);
        const snapshot = collector.sample();
        if (cfg.json) {
            try Renderer.renderJson(snapshot, sw);
        } else {
            try Renderer.renderSnapshotOnce(snapshot, sw, !cfg.no_color);
        }
        return;
    }

    // Interactive TUI Mode
    var term = Terminal.init();
    global_term = &term;
    defer global_term = null;

    _ = signal(SIGINT, handleSignal);
    _ = signal(SIGTERM, handleSignal);

    term.enterRawMode();
    term.enterAlternateScreen();
    defer term.restoreMode();

    var is_paused = false;
    var interval_ms = cfg.interval_ms;
    var last_update: i128 = 0;

    while (true) {
        const now = time_util.nanoTimestamp();
        const elapsed_ms = if (last_update > 0) @as(u64, @intCast(@max(0, @divTrunc(now - last_update, 1_000_000)))) else 0;

        if (!is_paused and (last_update == 0 or elapsed_ms >= interval_ms)) {
            const snapshot = collector.sample();
            const ws = Terminal.getWindowSize();
            try Renderer.renderDashboard(snapshot, sw, ws.ws_col, !cfg.no_color, interval_ms, is_paused);
            last_update = now;
        }

        // Poll non-blocking keyboard input
        if (Terminal.readKey()) |key| {
            switch (key) {
                'q', 'Q', 27, 3 => break, // q, Esc, Ctrl+C
                'p', 'P', ' ' => {
                    is_paused = !is_paused;
                    const snapshot = collector.sample();
                    const ws = Terminal.getWindowSize();
                    try Renderer.renderDashboard(snapshot, sw, ws.ws_col, !cfg.no_color, interval_ms, is_paused);
                },
                '+', '=' => {
                    if (interval_ms > 200) interval_ms -= 200;
                    const snapshot = collector.sample();
                    const ws = Terminal.getWindowSize();
                    try Renderer.renderDashboard(snapshot, sw, ws.ws_col, !cfg.no_color, interval_ms, is_paused);
                },
                '-', '_' => {
                    if (interval_ms < 10000) interval_ms += 200;
                    const snapshot = collector.sample();
                    const ws = Terminal.getWindowSize();
                    try Renderer.renderDashboard(snapshot, sw, ws.ws_col, !cfg.no_color, interval_ms, is_paused);
                },
                'r', 'R' => {
                    const snapshot = collector.sample();
                    const ws = Terminal.getWindowSize();
                    try Renderer.renderDashboard(snapshot, sw, ws.ws_col, !cfg.no_color, interval_ms, is_paused);
                    last_update = time_util.nanoTimestamp();
                },
                else => {},
            }
        }

        // Sleep 40ms to avoid busy loop while remaining responsive to keypresses
        time_util.sleepMs(40);
    }
}
