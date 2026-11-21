# local-status

A lightweight, high-performance, real-time command-line hardware monitor built for macOS (Apple Silicon & Intel) using Zig.

## Features

- **CPU Monitoring**: Overall utilization (User/System/Idle), per-core live gauge grid (Performance vs Efficiency cores), and 1/5/15-minute load averages via Darwin Mach APIs.
- **GPU Telemetry**: Real-time Apple Silicon integrated GPU utilization and model detection.
- **Memory Stats**: Physical RAM breakdown (App, Wired, Compressed, Free) and Swap usage matching Activity Monitor standards.
- **Storage Volumes**: Disk capacity and utilization metrics for APFS primary volumes (`/` and `/System/Volumes/Data`).
- **Interactive TUI Dashboard**: Alternate screen mode, smooth adaptive color gauges, and responsive keyboard controls.
- **Script-Friendly Modes**: Snapshot (`--once`) and JSON (`--json`) outputs for integrations with tmux, sketchybar, or scripts.
- **Zero Overhead**: Native binary compiled down to under 500 KB with no runtime virtual machine or interpreter.

## Building and Installation

### Prerequisites
- Zig (0.17 or compatible version)

### Build
```bash
zig build -Doptimize=ReleaseFast
```

### Install to Local Bin
```bash
zig build -Doptimize=ReleaseFast -p ~/.local
```
Make sure `~/.local/bin` is in your `$PATH`.

## Usage

```bash
# Launch interactive real-time dashboard
local-status

# Print a single-shot text summary and exit
local-status --once

# Output snapshot as JSON
local-status --json

# Set custom update interval in milliseconds
local-status -i 500

# Disable terminal colors
local-status --no-color
```

### Interactive Controls (TUI Mode)
- `q` / `Esc` / `Ctrl+C`: Quit and restore terminal
- `p` / `Space`: Pause / Resume updates
- `+` / `=`: Increase update frequency
- `-`: Decrease update frequency
- `r`: Force immediate refresh
- `h`: Show help info
