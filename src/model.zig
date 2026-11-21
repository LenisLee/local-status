const std = @import("std");

pub const CpuCore = struct {
    core_id: usize,
    is_performance: bool,
    usage_percent: f32,
};

pub const CpuStats = struct {
    total_usage: f32,
    user_percent: f32,
    system_percent: f32,
    idle_percent: f32,
    cores: []CpuCore,
    load_avg: [3]f64,
    core_count: usize,
    p_core_count: usize,
    e_core_count: usize,
    model_name: []const u8,
};

pub const GpuStats = struct {
    utilization_percent: f32,
    model_name: []const u8,
    is_apple_silicon: bool,
    available: bool,
};

pub const MemoryStats = struct {
    total_bytes: u64,
    used_bytes: u64,
    free_bytes: u64,
    active_bytes: u64,
    inactive_bytes: u64,
    wired_bytes: u64,
    compressed_bytes: u64,
    swap_total_bytes: u64,
    swap_used_bytes: u64,
    swap_free_bytes: u64,
    usage_percent: f32,
    swap_percent: f32,
};

pub const DiskMount = struct {
    mount_point: []const u8,
    fs_type: []const u8,
    total_bytes: u64,
    used_bytes: u64,
    free_bytes: u64,
    usage_percent: f32,
};

pub const SystemSnapshot = struct {
    timestamp: i64,
    cpu: CpuStats,
    gpu: GpuStats,
    memory: MemoryStats,
    disks: []const DiskMount,
};
