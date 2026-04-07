#!/bin/bash
# Setup script for directory_structure_profiling task

echo "=== Setting up directory_structure_profiling task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/directory_profile_result.json /tmp/directory_profile_gt.json \
      /tmp/directory_profile_start_time 2>/dev/null || true

for d in /home/ga/Cases/Directory_Profile_2024*/; do
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
echo "Pre-computing ground truth from image..."
python3 << 'PYEOF'
import subprocess, json, re, os, collections

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

# 1. Get filesystem info
try:
    fsstat_res = subprocess.run(["fsstat", IMAGE], capture_output=True, text=True, timeout=10)
    fs_type = "unknown"
    for line in fsstat_res.stdout.splitlines():
        if "File System Type:" in line:
            fs_type = line.split(":")[1].strip()
            break
except Exception:
    fs_type = "unknown"

# 2. Get full directory listing using fls
# -r for recursive, -p for full path
try:
    fls_res = subprocess.run(["fls", "-r", "-p", IMAGE], capture_output=True, text=True, timeout=60)
    lines = fls_res.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

total_dirs = 0
total_files = 0
allocated_files = 0
deleted_files = 0
max_depth = 0
extensions = collections.Counter()
paths = []

for line in lines:
    # Example format: 
    # + r/r 123: file.txt
    # ++ d/d * 124: dir/deleted_dir
    
    # Calculate depth from leading '+'
    depth_match = re.match(r'^(\++)', line)
    depth = len(depth_match.group(1)) if depth_match else 0
    if depth > max_depth:
        max_depth = depth
        
    stripped = re.sub(r'^[+\s]+', '', line)
    is_deleted = ' * ' in stripped
    
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
        
    type_field = m.group(1)
    inode = m.group(2)
    full_path = m.group(3).strip()
    
    # Clean up tab artifacts
    if '\t' in full_path:
        full_path = full_path.split('\t')[0].strip()
        
    # Ignore root itself or virtual files
    if full_path in ('.', '..') or full_path.startswith('$OrphanFiles'):
        continue
        
    name = os.path.basename(full_path)
    
    paths.append({
        "name": name,
        "full_path": full_path,
        "is_dir": type_field.endswith('d'),
        "is_deleted": is_deleted,
        "depth": depth
    })
    
    if type_field.endswith('d'):
        total_dirs += 1
    elif type_field.endswith('r') or type_field.endswith('v'):
        total_files += 1
        if is_deleted:
            deleted_files += 1
        else:
            allocated_files += 1
            
        # Tally extensions
        if not is_deleted and not name.startswith('$'):
            ext = os.path.splitext(name)[1].lower()
            if ext:
                extensions[ext] += 1
            else:
                extensions["<none>"] += 1

gt = {
    "fs_type": fs_type,
    "total_dirs": total_dirs,
    "total_files": total_files,
    "allocated_files": allocated_files,
    "deleted_files": deleted_files,
    "max_depth": max_depth,
    "extensions": dict(extensions),
    "paths": paths,
    "image_path": IMAGE
}

with open("/tmp/directory_profile_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth generated:")
print(f"  Filesystem: {fs_type}")
print(f"  Dirs: {total_dirs}, Files: {total_files} ({allocated_files} alloc, {deleted_files} del)")
print(f"  Max Depth: {max_depth}")
PYEOF

if [ ! -f /tmp/directory_profile_gt.json ]; then
    echo "WARNING: GT computation failed"
    echo '{"total_dirs":0,"total_files":0}' > /tmp/directory_profile_gt.json
fi

# ── Record start time ─────────────────────────────────────────────────────────
date +%s > /tmp/directory_profile_start_time

# ── Restart Autopsy cleanly ───────────────────────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Welcome screen..."
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
    kill_autopsy
    sleep 2
    launch_autopsy
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="