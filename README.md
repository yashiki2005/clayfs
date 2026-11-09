# ClayFS 🏺

> **Next-Generation APFS Virtual Drive & Instant Time Machine for macOS**  
> **English** | [日本語 (Japanese)](README.ja.md)

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![APFS CoW](https://img.shields.io/badge/Filesystem-APFS%20CoW-blue)](https://developer.apple.com/documentation/foundation/filemanager)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

ClayFS is a lightweight virtual drive and instant snapshot/rollback system for macOS that leverages **APFS Copy-on-Write (`clonefile(2)`)** to deliver zero-cost, millisecond-fast snapshots.

It allows developers to explore radical code refactoring, test breaking changes, or experiment on huge codebases with the confidence of an instant, 1-click rollback across both Finder and the terminal.

---

## ✨ Features

1. **Zero-Cost APFS & Btrfs CoW Snapshots**
   - Millisecond-fast snapshot creation via CoW reflink (`clonefile(2)` on macOS, `reflink` / `FICLONE` on Linux) without consuming additional disk space until files are modified.
2. **Cross-Platform Support (macOS & Linux)**
   - Unified `clayfs` CLI workflow across macOS (APFS sparsebundle) and Linux (Btrfs sparse image / loopback).
3. **Git-Like Volume Root Rollback**
   - Directly snapshot and roll back your entire mounted workspace root.
   - Automatically protects and ignores internal system directories (`.clayfs`, `.fseventsd`, `.Spotlight-V100`, etc.).
   - Includes subpath traversal protection (`../`) and safe atomic rollback if any restoration step fails.
4. **Native macOS Menu Bar App (`ClayFS.app`)**
   - Interactive timeline scrubber slider to preview past states and file changes.
   - 1-click snapshot creation, visual rollback confirmation with modified file counter, and customizable retention.
   - Fully asynchronous background polling ensures the UI thread never freezes.
5. **Seamless Online Volume Compaction (`compact`)**
   - Automatically reclaims unused blocks from virtual disk (macOS: `hdiutil compact`, Linux: `btrfs defragment` & `fstrim`).
6. **Configurable Retention Policy & Pruning (`prune`)**
   - Configure retention limits by snapshot count (`--keep N`) or snapshot age (`--days N`).
   - Automatically prunes expired snapshots in the background on snapshot creation.
7. **Automatic Change Monitoring Daemon (`watch`)**
   - Monitors file changes with debouncing and automatically snapshots when changes are detected (macOS: FSEvents, Linux: polling / inotify).
8. **Launch at Login & Drive Auto-Mount**
   - macOS: Modern `SMAppService` / LaunchAgents
   - Linux: `systemd --user` unit (`clayfs-automount.service`)
9. **Native 8-Language Localization (i18n)**
   - Fully localized in English, Japanese (日本語), Simplified Chinese (简体中文), Traditional Chinese (繁體中文), Spanish (Español), French (Français), German (Deutsch), and Korean (한국어). Auto-detects system language.

---

## 🚀 Quick Start

### Prerequisites
- **macOS**: macOS 14.0 (Sonoma) or later, Xcode 16 or Command Line Tools (Swift 6.0)
- **Linux**: Linux Kernel 4.5+ (Btrfs support), Swift 6.0, `btrfs-progs`, `libsqlite3-dev`

### Installation (Build & Install)

#### On macOS
```bash
git clone https://github.com/yashiki2005/clayfs.git
cd clayfs

# Build and install (CLI: ~/build/bin/clayfs, GUI: ~/Applications/ClayFS.app)
make install
```

#### On Linux (CLI Only)
```bash
git clone https://github.com/yashiki2005/clayfs.git
cd clayfs

# Install dependencies and Swift compiler (Ubuntu/Debian example)
# On Ubuntu 24.04+, swiftlang is available directly via apt:
sudo apt-get update
sudo apt-get install -y swiftlang btrfs-progs libsqlite3-dev

# (For Ubuntu 22.04 or other distributions, use the official Swift repository)
# curl -s https://archive.swiftlang.xyz/install.sh | sudo bash
# sudo apt-get install -y swiftlang btrfs-progs libsqlite3-dev

# Build and install (/usr/local/bin/clayfs)
./linux/build_linux.sh
```

> **Note**: Ensure `~/build/bin` is in your `$PATH` (e.g. `export PATH="$HOME/build/bin:$PATH"`).

---

## 💻 CLI Usage

### 1. Create a New Virtual Drive
```bash
# Create a 64GB sparse virtual drive named 'src'
clayfs create src --size 64g
```

### 2. Mount and Check Status
```bash
# Mount drive into Finder (mounted at /Volumes/src)
clayfs mount src

# List registered drives and mount states
clayfs status
```

### 3. Take Snapshots and View Timeline
```bash
# Take an immediate snapshot with a memo
clayfs snapshot src -m "Before major refactoring"

# View snapshot history timeline
clayfs timeline src
```

### 4. Diff Changes and Restore
```bash
# Show diff between working files and last snapshot
clayfs diff src

# Roll back the entire drive to a snapshot
clayfs restore src snap_20261108_052000

# Restore only a specific file or directory
clayfs restore src snap_20261108_052000 path/to/target.swift
```

### 5. Reclaim Disk Space (Compaction)
```bash
# Reclaim unused blocks after deleting files
clayfs compact src
```

### 6. Prune Old Snapshots
```bash
# Keep at most 30 snapshots and prune anything older than 14 days
clayfs prune src --keep 30 --days 14
```

### 7. Background Auto-Snapshot Daemon (Watch)
```bash
# Automatically create snapshots after 5 seconds of file quiescence
clayfs watch src
```

### 8. Startup & Auto-Mount Settings
```bash
# Enable or disable ClayFS launch at login
clayfs autostart on
clayfs autostart off

# Enable or disable auto-mount on launch for a drive
clayfs automount src on
clayfs automount src off
```

### 9. Multi-Language Help
```bash
clayfs help                 # Display help in system language
clayfs help --lang en       # Display in English
clayfs help --lang ja       # Display in Japanese
```

---

## 🖥️ Menu Bar App (ClayFS.app)

ClayFS includes a native SwiftUI menu bar application:

```bash
open ~/Applications/ClayFS.app
```

- **Status Bar Icon**: Shows mount status and active drive progress.
- **Timeline View**: Scrub through snapshot history with an intuitive visual slider.
- **Quick Actions**:
  - 📸 **Snapshot**: 1-click immediate snapshot
  - 🔄 **Compact**: Optimize and shrink drive image size
  - ⚙️ **Retention**: Adjust maximum count / days policy and prune on demand
  - ⚙️ **Startup**: Toggle launch at login and drive auto-mount from the footer settings
  - ⏱️ **Restore**: Safely rollback with a visual diff confirmation modal

---

## 🏛️ Architecture

```
┌────────────────────────────────────────────────────────┐
│                      ClayFS                            │
├───────────────────────────┬────────────────────────────┤
│     ClayFS App (GUI)      │      ClayFS CLI (main)     │
│   SwiftUI / Menu Bar      │    Command Line Tool       │
├───────────────────────────┴────────────────────────────┤
│                   ClayFSCore Framework                 │
│  - StorageManager (APFS Sparsebundle / hdiutil / CoW)  │
│  - SnapshotManager (clonefile(2) / Diff / Prune)       │
│  - TimelineDB (SQLite3 WAL mode with busy_timeout)     │
│  - FSEventsMonitor (Low-overhead kernel event watch)   │
│  - DriveRegistry (flock cross-process atomic registry) │
│  - LaunchAtLogin (SMAppService & LaunchAgent)          │
│  - AppLocale (System language detection / 8 langs)     │
├────────────────────────────────────────────────────────┤
│                   macOS Kernel / APFS                  │
│       APFS Sparsebundle Image (Copy-on-Write)          │
└────────────────────────────────────────────────────────┘
```

- **APFS Sparsebundle**: Dynamic virtual disk format that grows on demand and consumes space only as files are written.
- **SQLite3 WAL Mode**: High concurrency write-ahead logging with `sqlite3_busy_timeout` preventing locks between GUI and CLI.
- **Darwin FSEvents API**: Low-power, kernel-level file modification notifications.
- **Cross-Process `flock(2)`**: Reliable concurrency control between CLI commands and the background menu bar application.

---

## 🧪 Testing

Run comprehensive unit and integration tests (virtual drive creation, mounting, snapshotting, diffing, restoration rollback, security traversal checks, corruption recovery):

```bash
swift test
```

> - Integration tests that create disk images require `hdiutil` on macOS. On Linux only those are
>   skipped; unit tests (registry, SQLite, CoW cloning, path checks) still run.
> - Tests for the Linux tool (`linux/clayfs_btrfs`, btrfs based) live in `linux/`:
>   `linux/test_btrfs.sh` (needs root and btrfs), plus `python3 linux/test_parse_dump.py` and
>   `python3 linux/test_btrfs_logic.py`, which run without btrfs.

---

## 🐧 Linux tool (btrfs)

`linux/` contains a separate CLI that uses btrfs subvolumes directly instead of a disk image
(design: [docs/SPEC-linux-btrfs.md](docs/SPEC-linux-btrfs.md)).

| File | Purpose |
|---|---|
| `linux/clayfs_btrfs` | CLI that keeps history with a `work/` subvolume and read-only snapshots (Python) |
| `linux/install.sh` / `uninstall.sh` | Install / remove the scheduled jobs (hourly `run`, daily `gc`, weekly `scrub`) |
| `linux/migrate_from_dir.sh` | Copy a normal folder into `work/` and create the first commit |
| `clayfs_tool` / `clayfsctl` | The earlier macOS implementation (`make install-legacy`) |

---

## 📄 License

MIT License
