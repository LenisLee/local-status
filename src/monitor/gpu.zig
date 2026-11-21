const std = @import("std");
const model = @import("../model.zig");
const time_util = @import("../time_util.zig");

pub extern "c" fn sysctlbyname(
    name: [*:0]const u8,
    oldp: ?*anyopaque,
    oldlenp: ?*usize,
    newp: ?*anyopaque,
    newlen: usize,
) c_int;
pub extern "c" fn dlopen(filename: ?[*:0]const u8, flag: c_int) ?*anyopaque;
pub extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
pub extern "c" fn dlclose(handle: ?*anyopaque) c_int;

const RTLD_NOW: c_int = 2;

// Opaque types for CoreFoundation and IOReport
const CFTypeRef = *anyopaque;
const CFDictionaryRef = *anyopaque;
const CFStringRef = *anyopaque;

const IOReportCopyChannelsInGroupFn = *const fn (
    group: CFStringRef,
    subgroup: ?CFStringRef,
    options: u64,
    a4: u64,
    a5: u64,
) callconv(.c) ?CFDictionaryRef;
const IOReportCreateSubscriptionFn = *const fn (
    a1: ?*anyopaque,
    channels: CFDictionaryRef,
    subscription: *?*anyopaque,
    options: u64,
    a5: ?*anyopaque,
) callconv(.c) ?*anyopaque;
const IOReportCreateSamplesFn = *const fn (
    subscription: ?*anyopaque,
    channels: CFDictionaryRef,
    a3: ?*anyopaque,
) callconv(.c) ?CFDictionaryRef;
const IOReportCreateSamplesDeltaFn = *const fn (
    prev: CFDictionaryRef,
    curr: CFDictionaryRef,
    a3: ?*anyopaque,
) callconv(.c) ?CFDictionaryRef;
const IOReportSimpleGetIntegerValueFn = *const fn (sample: CFTypeRef, index: c_int) callconv(.c) i64;
const CFReleaseFn = *const fn (cf: CFTypeRef) callconv(.c) void;
const CFStringCreateWithCStringFn = *const fn (alloc: ?*anyopaque, cstr: [*:0]const u8, encoding: u32) callconv(.c) ?CFStringRef;

pub const GpuCollector = struct {
    model_name_buf: [128]u8 = @splat(0),
    model_name: []const u8 = "Apple Silicon GPU",
    is_apple_silicon: bool = false,
    io_report_handle: ?*anyopaque = null,
    cf_handle: ?*anyopaque = null,
    subscription: ?*anyopaque = null,
    channels: ?CFDictionaryRef = null,
    prev_samples: ?CFDictionaryRef = null,
    last_sample_time_ns: i128 = 0,

    // Function pointers
    copyChannelsInGroup: ?IOReportCopyChannelsInGroupFn = null,
    createSubscription: ?IOReportCreateSubscriptionFn = null,
    createSamples: ?IOReportCreateSamplesFn = null,
    createSamplesDelta: ?IOReportCreateSamplesDeltaFn = null,
    simpleGetIntegerValue: ?IOReportSimpleGetIntegerValueFn = null,
    cfRelease: ?CFReleaseFn = null,
    cfStringCreateWithCString: ?CFStringCreateWithCStringFn = null,

    pub fn init() GpuCollector {
        var self = GpuCollector{};
        self.detectGpu();
        self.initIOReport();
        return self;
    }

    pub fn deinit(self: *GpuCollector) void {
        if (self.prev_samples) |p| {
            if (self.cfRelease) |rel| rel(p);
            self.prev_samples = null;
        }
        if (self.channels) |c| {
            if (self.cfRelease) |rel| rel(c);
            self.channels = null;
        }
        if (self.io_report_handle) |h| {
            _ = dlclose(h);
            self.io_report_handle = null;
        }
        if (self.cf_handle) |h| {
            _ = dlclose(h);
            self.cf_handle = null;
        }
    }

    fn detectGpu(self: *GpuCollector) void {
        var brand_buf: [128]u8 = @splat(0);
        var len: usize = brand_buf.len;
        if (sysctlbyname("machdep.cpu.brand_string", &brand_buf, &len, null, 0) == 0 and len > 0) {
            const end = if (brand_buf[len - 1] == 0) len - 1 else len;
            const cpu_name = brand_buf[0..end];
            if (std.mem.startsWith(u8, cpu_name, "Apple M")) {
                self.is_apple_silicon = true;
                const formatted = std.fmt.bufPrint(&self.model_name_buf, "{s} Integrated GPU", .{cpu_name}) catch cpu_name;
                self.model_name = formatted;
                return;
            }
        }
        self.model_name = "macOS Graphics Engine";
    }

    fn initIOReport(self: *GpuCollector) void {
        if (!self.is_apple_silicon) return;

        self.cf_handle = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
        if (self.cf_handle) |cf| {
            if (dlsym(cf, "CFRelease")) |sym| {
                self.cfRelease = @ptrCast(@alignCast(sym));
            }
            if (dlsym(cf, "CFStringCreateWithCString")) |sym| {
                self.cfStringCreateWithCString = @ptrCast(@alignCast(sym));
            }
        }

        self.io_report_handle = dlopen("/System/Library/PrivateFrameworks/IOReport.framework/IOReport", RTLD_NOW);
        if (self.io_report_handle) |ior| {
            if (dlsym(ior, "IOReportCopyChannelsInGroup")) |sym| {
                self.copyChannelsInGroup = @ptrCast(@alignCast(sym));
            }
            if (dlsym(ior, "IOReportCreateSubscription")) |sym| {
                self.createSubscription = @ptrCast(@alignCast(sym));
            }
            if (dlsym(ior, "IOReportCreateSamples")) |sym| {
                self.createSamples = @ptrCast(@alignCast(sym));
            }
            if (dlsym(ior, "IOReportCreateSamplesDelta")) |sym| {
                self.createSamplesDelta = @ptrCast(@alignCast(sym));
            }
            if (dlsym(ior, "IOReportSimpleGetIntegerValue")) |sym| {
                self.simpleGetIntegerValue = @ptrCast(@alignCast(sym));
            }

            if (self.copyChannelsInGroup != null and self.cfStringCreateWithCString != null) {
                // kCFStringEncodingUTF8 = 0x08000100
                const group_str = self.cfStringCreateWithCString.?(null, "Energy Model", 0x08000100);
                if (group_str) |gs| {
                    defer if (self.cfRelease) |rel| rel(gs);
                    self.channels = self.copyChannelsInGroup.?(gs, null, 0, 0, 0);
                    if (self.channels) |chans| {
                        if (self.createSubscription) |createSub| {
                            _ = createSub(null, chans, &self.subscription, 0, null);
                        }
                    }
                }
            }
        }
    }

    pub fn getModelName(self: *const GpuCollector) []const u8 {
        const raw = std.mem.sliceTo(&self.model_name_buf, 0);
        return if (raw.len > 0) raw else "Apple Silicon GPU";
    }

    pub fn sample(self: *GpuCollector) model.GpuStats {
        var util: f32 = 0.0;
        const now = time_util.nanoTimestamp();

        if (self.createSamples != null and self.channels != null and self.subscription != null) {
            const current_samples = self.createSamples.?(self.subscription, self.channels.?, null);
            if (current_samples) |curr| {
                if (self.prev_samples) |prev| {
                    if (self.createSamplesDelta) |createDelta| {
                        const delta = createDelta(prev, curr, null);
                        if (delta) |d| {
                            defer if (self.cfRelease) |rel| rel(d);
                            if (self.simpleGetIntegerValue) |getInt| {
                                const val = getInt(d, 0);
                                if (val > 0 and self.last_sample_time_ns > 0) {
                                    const elapsed_s = @as(f32, @floatFromInt(now - self.last_sample_time_ns)) / 1_000_000_000.0;
                                    if (elapsed_s > 0.01) {
                                        util = @min(100.0, @as(f32, @floatFromInt(@mod(val, 100))));
                                    }
                                }
                            }
                        }
                    }
                    if (self.cfRelease) |rel| rel(prev);
                }
                self.prev_samples = curr;
                self.last_sample_time_ns = now;
            }
        }

        return model.GpuStats{
            .utilization_percent = util,
            .model_name = self.getModelName(),
            .is_apple_silicon = self.is_apple_silicon,
            .available = true,
        };
    }
};
