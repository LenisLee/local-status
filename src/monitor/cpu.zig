const std = @import("std");
const model = @import("../model.zig");

pub const CPU_STATE_USER = 0;
pub const CPU_STATE_SYSTEM = 1;
pub const CPU_STATE_IDLE = 2;
pub const CPU_STATE_NICE = 3;
pub const CPU_STATE_MAX = 4;

pub const host_cpu_load_info_data_t = extern struct {
    cpu_ticks: [CPU_STATE_MAX]c_uint,
};
pub const HOST_CPU_LOAD_INFO: c_int = 3;
pub const HOST_CPU_LOAD_INFO_COUNT: c_uint = @sizeOf(host_cpu_load_info_data_t) / @sizeOf(c_int);

pub const PROCESSOR_CPU_LOAD_INFO: c_int = 2;

pub extern "c" fn mach_host_self() c_uint;
pub extern "c" fn mach_task_self() c_uint;
pub extern "c" fn host_statistics64(
    host_priv: c_uint,
    flavor: c_int,
    host_info_out: [*]c_int,
    host_info_outCnt: *c_uint,
) c_int;
pub extern "c" fn host_processor_info(
    host: c_uint,
    flavor: c_int,
    out_processor_count: *c_uint,
    out_processor_info: *[*]c_int,
    out_processor_infoCnt: *c_uint,
) c_int;
pub extern "c" fn vm_deallocate(
    target_task: c_uint,
    address: usize,
    size: usize,
) c_int;
pub extern "c" fn getloadavg(loadavg: [*]f64, nelem: c_int) c_int;
pub extern "c" fn sysctlbyname(
    name: [*:0]const u8,
    oldp: ?*anyopaque,
    oldlenp: ?*usize,
    newp: ?*anyopaque,
    newlen: usize,
) c_int;

pub const MAX_CORES: usize = 128;

pub const CpuCollector = struct {
    prev_total_ticks: [CPU_STATE_MAX]u64 = @splat(0),
    prev_core_ticks: [MAX_CORES][CPU_STATE_MAX]u64 = @splat(@splat(0)),
    core_buf: [MAX_CORES]model.CpuCore = undefined,
    core_count: usize = 0,
    p_core_count: usize = 0,
    e_core_count: usize = 0,
    model_name_buf: [128]u8 = @splat(0),
    model_name: []const u8 = "CPU",
    initialized: bool = false,

    pub fn init() CpuCollector {
        var self = CpuCollector{};
        self.detectHardware();
        return self;
    }

    pub fn getModelName(self: *const CpuCollector) []const u8 {
        const raw = std.mem.sliceTo(&self.model_name_buf, 0);
        return if (raw.len > 0) raw else "Apple Silicon";
    }

    fn detectHardware(self: *CpuCollector) void {
        var len: usize = self.model_name_buf.len;
        _ = sysctlbyname("machdep.cpu.brand_string", &self.model_name_buf, &len, null, 0);

        var ncpu: u32 = 0;
        var ncpu_len: usize = @sizeOf(u32);
        if (sysctlbyname("hw.ncpu", &ncpu, &ncpu_len, null, 0) == 0) {
            self.core_count = @min(MAX_CORES, ncpu);
        }

        var p_cores: u32 = 0;
        var p_len: usize = @sizeOf(u32);
        if (sysctlbyname("hw.perflevel0.physicalcpu", &p_cores, &p_len, null, 0) == 0) {
            self.p_core_count = p_cores;
        }

        var e_cores: u32 = 0;
        var e_len: usize = @sizeOf(u32);
        if (sysctlbyname("hw.perflevel1.physicalcpu", &e_cores, &e_len, null, 0) == 0) {
            self.e_core_count = e_cores;
        }

        if (self.p_core_count == 0 and self.core_count > 0) {
            self.p_core_count = self.core_count;
        }
    }

    pub fn sample(self: *CpuCollector) model.CpuStats {
        var user_percent: f32 = 0.0;
        var sys_percent: f32 = 0.0;
        var idle_percent: f32 = 100.0;
        var total_usage: f32 = 0.0;

        // 1. Total CPU
        var info: host_cpu_load_info_data_t = undefined;
        var count: c_uint = HOST_CPU_LOAD_INFO_COUNT;
        if (host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, @ptrCast(&info), &count) == 0) {
            const cur_user = @as(u64, info.cpu_ticks[CPU_STATE_USER]);
            const cur_sys = @as(u64, info.cpu_ticks[CPU_STATE_SYSTEM]);
            const cur_idle = @as(u64, info.cpu_ticks[CPU_STATE_IDLE]);
            const cur_nice = @as(u64, info.cpu_ticks[CPU_STATE_NICE]);

            if (self.initialized) {
                const d_user = cur_user -| self.prev_total_ticks[CPU_STATE_USER];
                const d_sys = cur_sys -| self.prev_total_ticks[CPU_STATE_SYSTEM];
                const d_idle = cur_idle -| self.prev_total_ticks[CPU_STATE_IDLE];
                const d_nice = cur_nice -| self.prev_total_ticks[CPU_STATE_NICE];
                const total = d_user + d_sys + d_idle + d_nice;

                if (total > 0) {
                    const total_f = @as(f32, @floatFromInt(total));
                    user_percent = @as(f32, @floatFromInt(d_user)) * 100.0 / total_f;
                    sys_percent = @as(f32, @floatFromInt(d_sys)) * 100.0 / total_f;
                    idle_percent = @as(f32, @floatFromInt(d_idle)) * 100.0 / total_f;
                    total_usage = @min(100.0, @as(f32, @floatFromInt(d_user + d_sys + d_nice)) * 100.0 / total_f);
                }
            }

            self.prev_total_ticks[CPU_STATE_USER] = cur_user;
            self.prev_total_ticks[CPU_STATE_SYSTEM] = cur_sys;
            self.prev_total_ticks[CPU_STATE_IDLE] = cur_idle;
            self.prev_total_ticks[CPU_STATE_NICE] = cur_nice;
        }

        // 2. Per-core CPU
        var processor_count: c_uint = 0;
        var processor_info: [*]c_int = undefined;
        var processor_info_count: c_uint = 0;
        var sampled_cores: usize = 0;

        if (host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processor_count,
            &processor_info,
            &processor_info_count,
        ) == 0) {
            defer _ = vm_deallocate(mach_task_self(), @intFromPtr(processor_info), processor_info_count * @sizeOf(c_int));

            const n_proc = @min(MAX_CORES, @as(usize, processor_count));
            sampled_cores = n_proc;

            for (0..n_proc) |core_idx| {
                const base = core_idx * CPU_STATE_MAX;
                const c_user = @as(u64, @intCast(@max(0, processor_info[base + CPU_STATE_USER])));
                const c_sys = @as(u64, @intCast(@max(0, processor_info[base + CPU_STATE_SYSTEM])));
                const c_idle = @as(u64, @intCast(@max(0, processor_info[base + CPU_STATE_IDLE])));
                const c_nice = @as(u64, @intCast(@max(0, processor_info[base + CPU_STATE_NICE])));

                var core_usage: f32 = 0.0;
                if (self.initialized) {
                    const prev = self.prev_core_ticks[core_idx];
                    const d_u = c_user -| prev[CPU_STATE_USER];
                    const d_s = c_sys -| prev[CPU_STATE_SYSTEM];
                    const d_i = c_idle -| prev[CPU_STATE_IDLE];
                    const d_n = c_nice -| prev[CPU_STATE_NICE];
                    const total_c = d_u + d_s + d_i + d_n;
                    if (total_c > 0) {
                        core_usage = @min(100.0, @as(f32, @floatFromInt(d_u + d_s + d_n)) * 100.0 / @as(f32, @floatFromInt(total_c)));
                    }
                }

                self.prev_core_ticks[core_idx] = [CPU_STATE_MAX]u64{ c_user, c_sys, c_idle, c_nice };

                const is_perf = core_idx < self.p_core_count;
                self.core_buf[core_idx] = .{
                    .core_id = core_idx,
                    .is_performance = is_perf,
                    .usage_percent = core_usage,
                };
            }
        }

        // 3. Load average
        var load_avg: [3]f64 = [_]f64{ 0.0, 0.0, 0.0 };
        _ = getloadavg(&load_avg, 3);

        self.initialized = true;

        const effective_core_count = if (sampled_cores > 0) sampled_cores else self.core_count;

        return model.CpuStats{
            .total_usage = total_usage,
            .user_percent = user_percent,
            .system_percent = sys_percent,
            .idle_percent = idle_percent,
            .cores = self.core_buf[0..effective_core_count],
            .load_avg = load_avg,
            .core_count = effective_core_count,
            .p_core_count = self.p_core_count,
            .e_core_count = self.e_core_count,
            .model_name = self.getModelName(),
        };
    }
};
