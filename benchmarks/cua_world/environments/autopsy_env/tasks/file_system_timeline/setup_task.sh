#!/bin/bash
# Setup script for file_system_timeline task

echo "=== Setting up file_system_timeline task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up ──────────────────────────────────────────────────────────────────
rm -f /tmp/file_system_timeline_result.json /tmp/file_system_timeline_gt.json \
      /tmp/file_system_timeline_start_time 2>/dev/null || true

for d in /home/ga/Cases/Timeline_Analysis_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth (file timestamps) ───────────────────────────
echo "Pre-computing timeline ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, sys
from datetime import datetime

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

# Use fls -r -l for long format with timestamps
# Long format: TYPE/TYPE [*] INODE: NAME \t META \t ATIME \t MTIME \t CTIME \t CRTIME \t SIZE \t ...
try:
    result = subprocess.run(
        ["fls", "-r", "-l", "-m", "/", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    mactime_lines = result.stdout.splitlines()
    print(f"fls -m produced {len(mactime_lines)} lines")
except Exception as e:
    print(f"WARNING: fls -l -m failed: {e}, trying fls -r -l")
    mactime_lines = []

# Also try plain fls -r for file list
try:
    result2 = subprocess.run(
        ["fls", "-r", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    plain_lines = result2.stdout.splitlines()
    print(f"fls -r produced {len(plain_lines)} lines")
except Exception as e:
    print(f"WARNING: fls -r failed: {e}")
    plain_lines = []

# Parse file names and basic info
# fls format: TYPE [*] INODE: NAME  (TYPE can be r/r, -/r, etc.; * = deleted)
# Nested entries have leading "+ " or "++ "
files = []
for line in plain_lines:
    stripped = re.sub(r'^[+\s]+', '', line)
    is_deleted = ' * ' in stripped
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    if '\t' in name:
        name = name.split('\t')[0].strip()
    # Only regular files
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    if name in ('.', '..') or ':' in name:
        continue
    if name.startswith('$') and name not in ('$Recycle.Bin', '$RECYCLE.BIN'):
        continue
    files.append({
        "name": name,
        "inode": inode,
        "deleted": is_deleted
    })

# Try to get timestamps via istat for a few files (expensive but gives ground truth)
file_timestamps = []
for f in files[:20]:  # limit to first 20 to avoid timeout
    try:
        istat_result = subprocess.run(
            ["istat", IMAGE, f["inode"]],
            capture_output=True, text=True, timeout=10
        )
        # Parse mtime from istat output
        mtime_line = [l for l in istat_result.stdout.splitlines() if "Modified" in l]
        if mtime_line:
            # Format: "Modified:\t2010-01-01 00:00:00 (UTC)"
            m2 = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', mtime_line[0])
            if m2:
                file_timestamps.append({
                    "name": f["name"],
                    "inode": f["inode"],
                    "deleted": f["deleted"],
                    "mtime": m2.group(1)
                })
    except Exception:
        # istat can fail for deleted files — add with no timestamp
        file_timestamps.append({
            "name": f["name"],
            "inode": f["inode"],
            "deleted": f["deleted"],
            "mtime": "unknown"
        })

# Sort by mtime (most recent first)
known_times = [ft for ft in file_timestamps if ft["mtime"] != "unknown"]
known_times.sort(key=lambda x: x["mtime"], reverse=True)

gt = {
    "all_files": files,
    "total_files": len(files),
    "files_with_timestamps": file_timestamps,
    "most_recent_files": known_times[:5],
    "has_deleted_files": any(f["deleted"] for f in files),
    "image_path": IMAGE
}
with open("/tmp/file_system_timeline_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {len(files)} total files, {len(known_times)} with timestamps")
print(f"Most recent 5:")
for ft in known_times[:5]:
    print(f"  {ft['mtime']}: {ft['name']}")
PYEOF

if [ ! -f /tmp/file_system_timeline_gt.json ]; then
    echo "WARNING: GT computation failed"
    echo '{"all_files":[],"total_files":0,"files_with_timestamps":[],"most_recent_files":[],"has_deleted_files":false}' \
        > /tmp/file_system_timeline_gt.json
fi

# ── Record start time ─────────────────────────────────────────────────────────
date +%s > /tmp/file_system_timeline_start_time

# ── Launch Autopsy ────────────────────────────────────────────────────────────
kill_autopsy

echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false
while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        WELCOME_FOUND=true; break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        pgrep -f "/opt/autopsy" >/dev/null 2>&1 || launch_autopsy
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    kill_autopsy; sleep 2; launch_autopsy
    FINAL_ELAPSED=0
    while [ $FINAL_ELAPSED -lt 120 ]; do
        DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome" && WELCOME_FOUND=true && break
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        sleep 5; FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
    [ "$WELCOME_FOUND" = false ] && echo "FATAL: Welcome screen never appeared." && exit 1
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

echo "=== Task setup complete ==="
