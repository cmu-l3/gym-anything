#!/bin/bash
# Setup script for file_size_anomaly_detection task

echo "=== Setting up file_size_anomaly_detection task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up stale artifacts
rm -f /tmp/size_anomaly_result.json /tmp/size_anomaly_gt.json \
      /tmp/size_anomaly_start_time 2>/dev/null || true

for d in /home/ga/Cases/Size_Anomaly_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# 2. Verify disk image
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# 3. Pre-compute Ground Truth
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

try:
    # fls -r -l format:
    # TYPE/TYPE [*] INODE: NAME \t META \t ATIME \t MTIME \t CTIME \t CRTIME \t SIZE \t UID \t GID
    result = subprocess.run(
        ["fls", "-r", "-l", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

files = []
for line in lines:
    parts = line.split('\t')
    if len(parts) < 6:
        continue
    
    first_part = parts[0]
    stripped = re.sub(r'^[+\s]+', '', first_part)
    is_deleted = ' * ' in stripped
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
        
    type_field = m.group(1)
    name = m.group(3).strip()

    # Skip directories, dot files, ADS, and most system files
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    if name in ('.', '..') or ':' in name:
        continue
    if name.startswith('$') and name not in ('$Recycle.Bin', '$RECYCLE.BIN'):
        continue

    try:
        size = int(parts[5].strip())
    except ValueError:
        size = 0

    files.append({
        "name": name,
        "deleted": is_deleted,
        "size": size
    })

allocated_files = [f for f in files if not f["deleted"]]
deleted_files = [f for f in files if f["deleted"]]
total_alloc_bytes = sum(f["size"] for f in allocated_files)
total_del_bytes = sum(f["size"] for f in deleted_files)
ratio = (total_del_bytes / total_alloc_bytes) if total_alloc_bytes > 0 else 0.0

brackets = {"0": 0, "1-1023": 0, "1KB-99KB": 0, "100KB-999KB": 0, "1MB+": 0}
for f in files:
    s = f["size"]
    if s == 0: brackets["0"] += 1
    elif s < 1024: brackets["1-1023"] += 1
    elif s < 102400: brackets["1KB-99KB"] += 1
    elif s < 1024000: brackets["100KB-999KB"] += 1
    else: brackets["1MB+"] += 1

gt = {
    "total_files": len(files),
    "allocated_files": len(allocated_files),
    "deleted_files": len(deleted_files),
    "total_alloc_bytes": total_alloc_bytes,
    "total_del_bytes": total_del_bytes,
    "ratio": round(ratio, 2),
    "brackets": brackets,
    "file_names": [f["name"] for f in files]
}

with open("/tmp/size_anomaly_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth computed: {gt['total_files']} files")
print(f"Allocated: {gt['allocated_files']}, Deleted: {gt['deleted_files']}, Ratio: {gt['ratio']}")
PYEOF

if [ ! -f /tmp/size_anomaly_gt.json ]; then
    echo "WARNING: GT computation failed, creating empty GT"
    echo '{"total_files":0,"allocated_files":0,"deleted_files":0}' > /tmp/size_anomaly_gt.json
fi

# 4. Record task start time
date +%s > /tmp/size_anomaly_start_time

# 5. Relaunch Autopsy and prep UI
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear"
else
    # Maximize and take initial state screenshot
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "autopsy" | head -1 | cut -d' ' -f1)
    [ -n "$WID" ] && DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/task_initial_state.png
echo "=== Task setup complete ==="