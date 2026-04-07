#!/bin/bash
# Setup script for comprehensive_file_type_triage task

echo "=== Setting up comprehensive_file_type_triage task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/file_type_triage_result.json /tmp/file_type_triage_gt.json \
      /tmp/file_type_triage_start_time 2>/dev/null || true

for d in /home/ga/Cases/USB_Triage_2024*/; do
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
echo "Pre-computing file system ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, sys, os

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

files = []
dirs = 0

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
        
    if type_field.endswith('d'):
        dirs += 1
        continue
        
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue
        
    files.append({
        "name": name,
        "inode": inode,
        "deleted": is_deleted
    })

gt = {
    "total_files": len(files),
    "total_dirs": dirs,
    "allocated_count": sum(1 for f in files if not f["deleted"]),
    "deleted_count": sum(1 for f in files if f["deleted"]),
    "file_names": [f["name"] for f in files],
    "image_path": IMAGE
}

with open("/tmp/file_type_triage_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth computed: {gt['total_files']} files, {gt['total_dirs']} dirs.")
PYEOF

if [ ! -f /tmp/file_type_triage_gt.json ]; then
    echo "WARNING: Ground truth computation failed, creating empty GT"
    echo '{"total_files":0,"total_dirs":0,"allocated_count":0,"deleted_count":0,"file_names":[]}' > /tmp/file_type_triage_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/file_type_triage_start_time

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
    echo "ERROR: Autopsy Welcome screen did NOT appear."
fi

# Wait for UI to settle, then take screenshot
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="