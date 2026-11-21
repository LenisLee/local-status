const std = @import("std");
const model = @import("../model.zig");
const time_util = @import("../time_util.zig");
const CpuCollector = @import("cpu.zig").CpuCollector;
const MemoryCollector = @import("memory.zig").MemoryCollector;
const DiskCollector = @import("disk.zig").DiskCollector;
const MAX_DISKS = @import("disk.zig").MAX_DISKS;
const GpuCollector = @import("gpu.zig").GpuCollector;

pub const SystemCollector = struct {
    cpu_col: CpuCollector,
    mem_col: MemoryCollector,
    gpu_col: GpuCollector,
    disk_buf: [MAX_DISKS]model.DiskMount = undefined,

    pub fn init() SystemCollector {
        return SystemCollector{
            .cpu_col = CpuCollector.init(),
            .mem_col = MemoryCollector.init(),
            .gpu_col = GpuCollector.init(),
        };
    }

    pub fn deinit(self: *SystemCollector) void {
        self.gpu_col.deinit();
    }

    pub fn sample(self: *SystemCollector) model.SystemSnapshot {
        const cpu_stats = self.cpu_col.sample();
        const mem_stats = self.mem_col.sample();
        const gpu_stats = self.gpu_col.sample();
        const disks = DiskCollector.sample(&self.disk_buf);

        return model.SystemSnapshot{
            .timestamp = time_util.milliTimestamp(),
            .cpu = cpu_stats,
            .gpu = gpu_stats,
            .memory = mem_stats,
            .disks = disks,
        };
    }
};
