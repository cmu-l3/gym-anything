#!/bin/bash
# Setup script for allocation_delta_correlation_analysis task

echo "=== Setting up allocation_delta_correlation_analysis task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/delta_result.json /tmp/delta_gt.json /tmp/delta_start_time 2>/dev/null || true

# Remove old Autopsy cases
for d in /home/ga/Cases/Delta_Analysis_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

# Create required directories
mkdir -p /home/ga/Reports
mkdir -p /home/ga/mnt/usb_ro
chown -R ga:ga /home/ga/Reports/ /home/ga/mnt/ 2>/dev/null || true

# Ensure image is NOT mounted from a previous run
sudo umount /home/ga/mnt/usb_ro 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth for .txt files ───────────────────────────────
echo "Pre-computing ground truth for .txt files..."
python3 << 'PYEOF'
import subprocess, json, re

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

allocated_txt = []
deleted_txt = []

for line in lines:
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
        
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue
        
    if name.lower().endswith('.txt'):
        if is_deleted:
            deleted_txt.append({"name": name, "inode": inode})
        else:
            allocated_txt.append({"name": name, "inode": inode})

gt = {
    "allocated_txt_files": allocated_txt,
    "allocated_txt_count": len(allocated_txt),
    "deleted_txt_files": deleted_txt,
    "deleted_txt_count": len(deleted_txt),
    "total_txt_count": len(allocated_txt) + len(deleted_txt),
    "deleted_txt_names": [f["name"] for f in deleted_txt]
}

with open("/tmp/delta_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth computed:")
print(f"  Allocated .txt: {gt['allocated_txt_count']}")
print(f"  Deleted .txt:   {gt['deleted_txt_count']}")
print(f"  Total .txt:     {gt['total_txt_count']}")
PYEOF

if [ ! -f /tmp/delta_gt.json ]; then
    echo "WARNING: GT computation failed, creating empty GT"
    echo '{"allocated_txt_count":0,"deleted_txt_count":0,"total_txt_count":0,"deleted_txt_names":[]}' > /tmp/delta_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/delta_start_time

# ── Kill any running Autopsy and Relaunch ─────────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy Welcome screen..."
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
            echo "Autopsy died, relaunching at ${WELCOME_ELAPSED}s..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear."
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="