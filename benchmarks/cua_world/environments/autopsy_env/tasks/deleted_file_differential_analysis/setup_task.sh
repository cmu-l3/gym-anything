#!/bin/bash
# Setup script for deleted_file_differential_analysis task

echo "=== Setting up deleted_file_differential_analysis task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/deletion_differential_result.json /tmp/deletion_differential_gt.json \
      /tmp/task_start_time.txt /tmp/task_initial.png 2>/dev/null || true

for d in /home/ga/Cases/Deletion_Differential_2024*/; do
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

# ── Pre-compute TSK ground truth ──────────────────────────────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, sys

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

try:
    result = subprocess.run(
        ["fls", "-r", "-l", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

allocated_files = []
deleted_files = []

for line in lines:
    if not line.strip():
        continue
    
    # Strip leading depth indicators (+ symbols and spaces)
    stripped = re.sub(r'^[+\s]+', '', line)
    is_deleted = ' * ' in stripped
    
    # Match: TYPE [*] INODE: NAME \t META ...
    # Ex: r/r * 123-128-1: file.txt    2020-01-01 ...
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+([^\t]+)', stripped)
    if not m:
        continue
        
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    
    # Skip directories and non-regular files
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
        
    # Skip system/metadata files
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue
        
    # Extract extension
    ext = "none"
    if '.' in name and not name.startswith('.'):
        ext = name.split('.')[-1].lower()
        
    file_record = {"name": name, "inode": inode, "ext": ext}
    
    if is_deleted:
        deleted_files.append(file_record)
    else:
        allocated_files.append(file_record)

alloc_count = len(allocated_files)
del_count = len(deleted_files)
ratio = round(del_count / alloc_count, 2) if alloc_count > 0 else 0.0

gt = {
    "allocated_files": allocated_files,
    "deleted_files": deleted_files,
    "allocated_count": alloc_count,
    "deleted_count": del_count,
    "deletion_ratio": ratio,
    "allocated_names": [f["name"].lower() for f in allocated_files],
    "deleted_names": [f["name"].lower() for f in deleted_files],
    "image_path": IMAGE
}

with open("/tmp/deletion_differential_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {alloc_count} allocated, {del_count} deleted (Ratio: {ratio})")
PYEOF

if [ ! -f /tmp/deletion_differential_gt.json ]; then
    echo "WARNING: Ground truth computation failed, creating empty GT"
    echo '{"allocated_files":[],"deleted_files":[],"allocated_count":0,"deleted_count":0}' > /tmp/deletion_differential_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── Kill any running Autopsy ──────────────────────────────────────────────────
kill_autopsy

# ── Launch Autopsy and wait for Welcome screen ────────────────────────────────
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy process to start..."
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected after ${WELCOME_ELAPSED}s"
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "WARNING: Welcome screen not detected cleanly, but continuing..."
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Autopsy" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="