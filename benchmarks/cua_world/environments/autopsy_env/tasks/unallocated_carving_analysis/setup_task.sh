#!/bin/bash
# Setup script for unallocated_carving_analysis task

echo "=== Setting up unallocated_carving_analysis task ==="
source /workspace/scripts/task_utils.sh

# ── 1. Clean up stale artifacts ────────────────────────────────────────────────
rm -f /tmp/carving_analysis_result.json /tmp/carving_analysis_gt.json \
      /tmp/carving_analysis_start_time 2>/dev/null || true

for d in /home/ga/Cases/Carving_Analysis_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
rm -f /home/ga/Reports/carved_*.txt /home/ga/Reports/allocated_*.txt /home/ga/Reports/carving_*.txt
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── 2. Verify disk image ───────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/jpeg_search.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── 3. Pre-compute Ground Truth (Allocated vs Raw JPEGs) ───────────────────────
echo "Pre-computing ground truth from image..."
python3 << 'PYEOF'
import subprocess, json, re, sys

IMAGE = "/home/ga/evidence/jpeg_search.dd"

# Use fls to get allocated files
try:
    result = subprocess.run(["fls", "-r", IMAGE], capture_output=True, text=True, timeout=60)
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

allocated_files = []
for line in lines:
    if ' * ' in line:  # Skip deleted/unallocated
        continue
    stripped = re.sub(r'^[+\s]+', '', line)
    m = re.match(r'^([\w/-]+)\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m: continue
    
    type_field, inode, name = m.group(1), m.group(2), m.group(3).strip()
    if '\t' in name: name = name.split('\t')[0].strip()
    if type_field.endswith('d') or type_field.endswith('v'): continue
    if name in ('.', '..') or name.startswith('$') or ':' in name: continue
    allocated_files.append(name)

# Raw signature search for JPEGs (SOI + APP0/APP1 markers) to estimate total carved
try:
    with open(IMAGE, "rb") as f:
        data = f.read()
    raw_jpegs = len(re.findall(b'\xff\xd8\xff\xe0|\xff\xd8\xff\xe1', data))
except Exception as e:
    print(f"WARNING: Raw read failed: {e}")
    raw_jpegs = 0

estimated_carved = max(0, raw_jpegs - len(allocated_files))

gt = {
    "image_path": IMAGE,
    "allocated_files": allocated_files,
    "allocated_count": len(allocated_files),
    "raw_jpeg_count": raw_jpegs,
    "estimated_carved_count": estimated_carved
}

with open("/tmp/carving_analysis_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground Truth -> Allocated files: {gt['allocated_count']}, Total Raw JPEGs: {gt['raw_jpeg_count']}, Estimated Carved: {gt['estimated_carved_count']}")
PYEOF

if [ ! -f /tmp/carving_analysis_gt.json ]; then
    echo '{"allocated_count":0, "raw_jpeg_count":0, "estimated_carved_count":0}' > /tmp/carving_analysis_gt.json
fi

# ── 4. Record task start time ──────────────────────────────────────────────────
date +%s > /tmp/carving_analysis_start_time

# ── 5. Launch Autopsy ──────────────────────────────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

# Wait for Welcome screen
WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected."
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "WARNING: Welcome screen might not have appeared properly, but proceeding."
fi

# Dismiss popups
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize main window if available
MAIN_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "autopsy" | grep -v "Welcome" | awk '{print $1}' | head -1)
if [ -n "$MAIN_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$MAIN_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga
echo "=== Setup complete ==="