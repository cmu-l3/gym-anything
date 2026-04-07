#!/bin/bash
# Setup script for forensic_report_generation task

echo "=== Setting up forensic_report_generation task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up stale artifacts from previous runs
rm -f /tmp/forensic_report_result.json /tmp/forensic_report_gt.json \
      /tmp/task_start_time.txt /tmp/forensic_initial.png 2>/dev/null || true

for d in /home/ga/Cases/DA_Report_Case_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true
rm -f /home/ga/Reports/case_summary_memo.txt 2>/dev/null || true

# 2. Verify disk image exists
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# 3. Pre-compute ground truth (File counts for plausibility check)
echo "Pre-computing ground truth from TSK..."
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

total_files = 0
allocated_files = 0
deleted_files = 0

for line in lines:
    stripped = re.sub(r'^[+\s]+', '', line)
    is_deleted = ' * ' in stripped
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
    type_field = m.group(1)
    
    # Only count regular files, not directories
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
        
    total_files += 1
    if is_deleted:
        deleted_files += 1
    else:
        allocated_files += 1

gt = {
    "image_path": IMAGE,
    "total_files": total_files,
    "allocated_files": allocated_files,
    "deleted_files": deleted_files
}

with open("/tmp/forensic_report_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {total_files} total files ({allocated_files} allocated, {deleted_files} deleted)")
PYEOF

if [ ! -f /tmp/forensic_report_gt.json ]; then
    echo "WARNING: Ground truth computation failed, using fallback"
    echo '{"total_files": 100, "allocated_files": 50, "deleted_files": 50}' > /tmp/forensic_report_gt.json
fi

# 4. Record task start time for anti-gaming (must happen BEFORE launching Autopsy)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Launch Autopsy safely
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy window..."
wait_for_autopsy_window 300

# Try to nudge the Welcome screen
WELCOME_TIMEOUT=120
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected."
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Autopsy main window
AUTOPSY_WID=$(DISPLAY=:1 wmctrl -l | grep -i "autopsy" | grep -v "Welcome" | awk '{print $1}' | head -1)
if [ -n "$AUTOPSY_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$AUTOPSY_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$AUTOPSY_WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/forensic_initial.png

echo "=== Task setup complete ==="