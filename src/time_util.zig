const std = @import("std");

pub const timeval = extern struct {
    tv_sec: isize,
    tv_usec: i32,
};

pub extern "c" fn usleep(usec: c_uint) c_int;
pub extern "c" fn gettimeofday(tv: *timeval, tz: ?*anyopaque) c_int;

pub fn milliTimestamp() i64 {
    var tv: timeval = undefined;
    _ = gettimeofday(&tv, null);
    return @as(i64, tv.tv_sec) * 1000 + @divTrunc(@as(i64, tv.tv_usec), 1000);
}

pub fn nanoTimestamp() i128 {
    var tv: timeval = undefined;
    _ = gettimeofday(&tv, null);
    return @as(i128, tv.tv_sec) * 1_000_000_000 + @as(i128, tv.tv_usec) * 1000;
}

pub fn sleepMs(ms: u64) void {
    _ = usleep(@intCast(ms * 1000));
}
