const std = @import("std");
const model = @import("../model.zig");

pub const HOST_VM_INFO64: c_int = 4;
pub const HOST_VM_INFO64_COUNT: c_uint = 38;

pub const vm_statistics64_data_t = extern struct {
    free_count: u32,
    active_count: u32,
    inactive_count: u32,
    wire_count: u32,
    zero_fill_count: u64,
    reactivations: u64,
    pageins: u64,
    pageouts: u64,
    faults: u64,
    cow_faults: u64,
    lookups: u64,
    hits: u64,
    purges: u64,
    purgeable_count: u32,
    speculative_count: u32,
    decompressions: u64,
    compressions: u64,
    swapins: u64,
    swapouts: u64,
    compressor_page_count: u32,
    throttled_count: u32,
    external_page_count: u32,
    internal_page_count: u32,
    total_uncompressed_pages_in_compressor: u64,
};

pub const xsw_usage = extern struct {
    xsu_total: u64,
    xsu_avail: u64,
    xsu_used: u64,
    xsu_pagesize: u32,
    xsu_encrypted: bool,
};

pub extern "c" fn mach_host_self() c_uint;
pub extern "c" fn host_statistics64(
    host_priv: c_uint,
    flavor: c_int,
    host_info_out: [*]c_int,
    host_info_outCnt: *c_uint,
) c_int;
pub extern "c" fn sysctlbyname(
    name: [*:0]const u8,
    oldp: ?*anyopaque,
    oldlenp: ?*usize,
    newp: ?*anyopaque,
    newlen: usize,
) c_int;

pub const MemoryCollector = struct {
    total_mem: u64 = 0,
    page_size: u64 = 16384,

    pub fn init() MemoryCollector {
        var self = MemoryCollector{};
        var mem: u64 = 0;
        var len: usize = @sizeOf(u64);
        if (sysctlbyname("hw.memsize", &mem, &len, null, 0) == 0) {
            self.total_mem = mem;
        }

        var ps: u32 = 0;
        var ps_len: usize = @sizeOf(u32);
        if (sysctlbyname("hw.pagesize", &ps, &ps_len, null, 0) == 0 and ps > 0) {
            self.page_size = ps;
        }
        return self;
    }

    pub fn sample(self: *const MemoryCollector) model.MemoryStats {
        var vm_stat: vm_statistics64_data_t = undefined;
        var count: c_uint = HOST_VM_INFO64_COUNT;
        var active: u64 = 0;
        var inactive: u64 = 0;
        var wired: u64 = 0;
        var compressed: u64 = 0;
        var free: u64 = 0;

        if (host_statistics64(mach_host_self(), HOST_VM_INFO64, @ptrCast(&vm_stat), &count) == 0) {
            active = @as(u64, vm_stat.active_count) * self.page_size;
            inactive = @as(u64, vm_stat.inactive_count) * self.page_size;
            wired = @as(u64, vm_stat.wire_count) * self.page_size;
            compressed = @as(u64, vm_stat.compressor_page_count) * self.page_size;
            free = @as(u64, vm_stat.free_count) * self.page_size;
        }

        const used = active + wired + compressed;
        var usage_percent: f32 = 0.0;
        if (self.total_mem > 0) {
            usage_percent = @min(100.0, @as(f32, @floatFromInt(used)) * 100.0 / @as(f32, @floatFromInt(self.total_mem)));
        }

        // Swap usage
        var swap: xsw_usage = undefined;
        var swap_len: usize = @sizeOf(xsw_usage);
        var swap_total: u64 = 0;
        var swap_used: u64 = 0;
        var swap_free: u64 = 0;
        var swap_percent: f32 = 0.0;
        if (sysctlbyname("vm.swapusage", &swap, &swap_len, null, 0) == 0) {
            swap_total = swap.xsu_total;
            swap_used = swap.xsu_used;
            swap_free = swap.xsu_avail;
            if (swap_total > 0) {
                swap_percent = @min(100.0, @as(f32, @floatFromInt(swap_used)) * 100.0 / @as(f32, @floatFromInt(swap_total)));
            }
        }

        return model.MemoryStats{
            .total_bytes = self.total_mem,
            .used_bytes = used,
            .free_bytes = free,
            .active_bytes = active,
            .inactive_bytes = inactive,
            .wired_bytes = wired,
            .compressed_bytes = compressed,
            .swap_total_bytes = swap_total,
            .swap_used_bytes = swap_used,
            .swap_free_bytes = swap_free,
            .usage_percent = usage_percent,
            .swap_percent = swap_percent,
        };
    }
};
