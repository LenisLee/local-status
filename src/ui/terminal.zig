const std = @import("std");

pub const winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};
pub const TIOCGWINSZ: c_ulong = 0x40087468;

pub const termios = extern struct {
    c_iflag: c_ulong,
    c_oflag: c_ulong,
    c_cflag: c_ulong,
    c_lflag: c_ulong,
    c_cc: [32]u8,
    c_ispeed: c_ulong,
    c_ospeed: c_ulong,
};
pub const TCSANOW: c_int = 0;
pub const STDIN_FILENO: c_int = 0;
pub const STDOUT_FILENO: c_int = 1;

pub const ECHO: c_ulong = 0x00000008;
pub const ICANON: c_ulong = 0x00000100;
pub const ISIG: c_ulong = 0x00000080;
pub const VMIN: usize = 16;
pub const VTIME: usize = 17;

pub extern "c" fn tcgetattr(fd: c_int, termios_p: *termios) c_int;
pub extern "c" fn tcsetattr(fd: c_int, optional_actions: c_int, termios_p: *const termios) c_int;
pub extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
pub extern "c" fn read(fd: c_int, buf: [*]u8, nbyte: usize) isize;
pub extern "c" fn write(fd: c_int, buf: [*]const u8, count: usize) isize;

pub const StdoutWriter = struct {
    pub const Error = error{};

    pub fn writeAll(_: StdoutWriter, bytes: []const u8) Error!void {
        _ = write(STDOUT_FILENO, bytes.ptr, bytes.len);
    }

    pub fn print(self: StdoutWriter, comptime fmt: []const u8, args: anytype) Error!void {
        var buf: [4096]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        try self.writeAll(msg);
    }
};

pub const Terminal = struct {
    orig_termios: ?termios = null,
    in_alternate_screen: bool = false,

    pub fn init() Terminal {
        return Terminal{};
    }

    pub fn enterRawMode(self: *Terminal) void {
        var raw: termios = undefined;
        if (tcgetattr(STDIN_FILENO, &raw) == 0) {
            self.orig_termios = raw;
            raw.c_lflag &= ~(ECHO | ICANON);
            raw.c_cc[VMIN] = 0;
            raw.c_cc[VTIME] = 0;
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &raw);
        }
    }

    pub fn restoreMode(self: *Terminal) void {
        if (self.orig_termios) |orig| {
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &orig);
            self.orig_termios = null;
        }
        if (self.in_alternate_screen) {
            self.leaveAlternateScreen();
        }
    }

    pub fn enterAlternateScreen(self: *Terminal) void {
        const sw = StdoutWriter{};
        _ = sw.writeAll("\x1b[?1049h\x1b[?25l\x1b[H") catch {};
        self.in_alternate_screen = true;
    }

    pub fn leaveAlternateScreen(self: *Terminal) void {
        const sw = StdoutWriter{};
        _ = sw.writeAll("\x1b[?25h\x1b[?1049l") catch {};
        self.in_alternate_screen = false;
    }

    pub fn getWindowSize() winsize {
        var ws: winsize = .{ .ws_row = 24, .ws_col = 80, .ws_xpixel = 0, .ws_ypixel = 0 };
        _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws);
        if (ws.ws_col == 0) ws.ws_col = 80;
        if (ws.ws_row == 0) ws.ws_row = 24;
        return ws;
    }

    pub fn readKey() ?u8 {
        var buf: [1]u8 = undefined;
        const n = read(STDIN_FILENO, &buf, 1);
        if (n > 0) return buf[0];
        return null;
    }
};
