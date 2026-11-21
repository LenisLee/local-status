const std = @import("std");

pub const Config = struct {
    interval_ms: u64 = 1000,
    once: bool = false,
    json: bool = false,
    no_color: bool = false,
    show_help: bool = false,
    show_version: bool = false,

    pub fn parse(args: []const []const u8) Config {
        var cfg: Config = .{};
        var i: usize = 1; // skip binary name
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                cfg.show_help = true;
            } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
                cfg.show_version = true;
            } else if (std.mem.eql(u8, arg, "-1") or std.mem.eql(u8, arg, "--once")) {
                cfg.once = true;
            } else if (std.mem.eql(u8, arg, "--json")) {
                cfg.json = true;
            } else if (std.mem.eql(u8, arg, "--no-color")) {
                cfg.no_color = true;
            } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--interval")) {
                if (i + 1 < args.len) {
                    i += 1;
                    if (std.fmt.parseInt(u64, args[i], 10)) |val| {
                        cfg.interval_ms = @max(100, val);
                    } else |_| {}
                }
            }
        }
        return cfg;
    }

    pub fn printHelp(writer: anytype) !void {
        try writer.print(
            \\local-status v0.1.0 - Real-time System Hardware Monitor (macOS)
            \\
            \\USAGE:
            \\    local-status [OPTIONS]
            \\
            \\OPTIONS:
            \\    -i, --interval <ms>  Update frequency in milliseconds (default: 1000)
            \\    -1, --once           Print a single snapshot and exit
            \\        --json           Output metrics as JSON (single snapshot)
            \\        --no-color       Disable ANSI color escape codes
            \\    -h, --help           Show this help message
            \\    -v, --version        Show version
            \\
            \\INTERACTIVE KEYS (TUI Mode):
            \\    q, Esc, Ctrl+C       Quit application
            \\    p                    Pause / Resume updates
            \\    +, =                 Increase refresh speed (-200ms)
            \\    -                    Decrease refresh speed (+200ms)
            \\    r                    Manual refresh
            \\
        , .{});
    }
};
