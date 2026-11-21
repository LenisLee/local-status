const std = @import("std");
const model = @import("../model.zig");

pub const statvfs_t = extern struct {
    f_bsize: c_ulong,
    f_frsize: c_ulong,
    f_blocks: c_uint,
    f_bfree: c_uint,
    f_bavail: c_uint,
    f_files: c_uint,
    f_ffree: c_uint,
    f_favail: c_uint,
    f_fsid: c_ulong,
    f_flag: c_ulong,
    f_namemax: c_ulong,
};
pub extern "c" fn statvfs(path: [*:0]const u8, buf: *statvfs_t) c_int;

pub const MAX_DISKS: usize = 16;

pub const DiskCollector = struct {
    pub fn sample(disk_buf: *[MAX_DISKS]model.DiskMount) []const model.DiskMount {
        const candidate_paths = [_]struct { path: [*:0]const u8, label: []const u8, fs: []const u8 }{
            .{ .path = "/System/Volumes/Data", .label = "Data (/System/Volumes/Data)", .fs = "APFS" },
            .{ .path = "/", .label = "System (/)", .fs = "APFS" },
        };

        var count: usize = 0;
        for (candidate_paths) |cand| {
            if (count >= MAX_DISKS) break;
            var buf: statvfs_t = undefined;
            if (statvfs(cand.path, &buf) == 0) {
                const frsize = @as(u64, buf.f_frsize);
                const total = @as(u64, buf.f_blocks) * frsize;
                const free = @as(u64, buf.f_bavail) * frsize;
                const used = total -| free;
                var usage_percent: f32 = 0.0;
                if (total > 0) {
                    usage_percent = @min(100.0, @as(f32, @floatFromInt(used)) * 100.0 / @as(f32, @floatFromInt(total)));
                }

                disk_buf[count] = .{
                    .mount_point = cand.label,
                    .fs_type = cand.fs,
                    .total_bytes = total,
                    .used_bytes = used,
                    .free_bytes = free,
                    .usage_percent = usage_percent,
                };
                count += 1;
            }
        }
        return disk_buf[0..count];
    }
};
