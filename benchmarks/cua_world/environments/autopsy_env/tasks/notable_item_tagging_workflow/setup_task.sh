#!/bin/bash
# Setup script for notable_item_tagging_workflow task

echo "=== Setting up notable_item_tagging_workflow task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/tagging_workflow_result.json /tmp/tagging_workflow_gt.json \
      /tmp/tagging_workflow_start_time 2>/dev/null || true

for d in /home/ga/Cases/Court_Prep_2024*/; do
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

# ── Pre-compute TSK ground truth (Deleted vs Allocated) ───────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, sys

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

try:
    result = subprocess.run(
        ["fls", "-r", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

deleted_files = []
allocated_files = []

for line in lines:
    # fls output format:
    #   Allocated:  "r/r INODE: NAME"
    #   Deleted:    "-/r * INODE: NAME"  OR  "r/r * INODE: NAME"
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
    
    # Skip directories (type ends in d) or virtual files (type ends in v)
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
        
    # Skip system/metadata files and streams
    if name in ('.', '..') or ':' in name:
        continue
    if name.startswith('$') and name not in ('$Recycle.Bin', '$RECYCLE.BIN'):
        continue
        
    if is_deleted:
        deleted_files.append({"name": name, "inode": inode})
    else:
        allocated_files.append({"name": name, "inode": inode})

gt = {
    "deleted_files": deleted_files,
    "allocated_files": allocated_files,
    "total_deleted": len(deleted_files),
    "total_allocated": len(allocated_files),
    "deleted_names": [f["name"] for f in deleted_files],
    "allocated_names": [f["name"] for f in allocated_files]
}

with open("/tmp/tagging_workflow_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth computed: {gt['total_deleted']} deleted, {gt['total_allocated']} allocated regular files.")
PYEOF

if [ ! -f /tmp/tagging_workflow_gt.json ]; then
    echo "WARNING: Ground truth computation failed, creating empty GT"
    echo '{"deleted_files":[],"allocated_files":[],"total_deleted":0,"total_allocated":0,"deleted_names":[],"allocated_names":[]}' > /tmp/tagging_workflow_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/tagging_workflow_start_time

# ── Kill any running Autopsy and relaunch ─────────────────────────────────────
kill_autopsy
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
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy died, relaunching..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "WARNING: Welcome screen didn't appear, attempting to continue anyway"
fi

# Dismiss popups
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="