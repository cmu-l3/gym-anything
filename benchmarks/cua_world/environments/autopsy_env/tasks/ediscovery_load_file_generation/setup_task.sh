#!/bin/bash
# Setup script for ediscovery_load_file_generation task

echo "=== Setting up eDiscovery Load File Generation task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/ediscovery_result.json /tmp/ediscovery_gt.json /tmp/ediscovery_start_time 2>/dev/null || true

for d in /home/ga/Cases/Litigation_Support_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports/eDiscovery/Natives
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth (Allocated User Files) ───────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, hashlib, os

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

allocated_files = []

for line in lines:
    stripped = re.sub(r'^[+\s]+', '', line)
    
    # Exclude deleted files
    if ' * ' in stripped:
        continue
        
    m = re.match(r'^([\w/-]+)\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
        
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    
    # Handle tab-separated metadata
    if '\t' in name:
        name = name.split('\t')[0].strip()
        
    # Exclude directories (type ends with d)
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
        
    # Exclude system/hidden metafiles and current/parent dir markers
    if name in ('.', '..'):
        continue
    if name.startswith('$') and name not in ('$Recycle.Bin', '$RECYCLE.BIN'):
        continue
    if ':' in name:
        continue # Skip Alternate Data Streams
        
    # Valid allocated user file found
    # Extract file to hash it
    try:
        icat_result = subprocess.run(
            ["icat", IMAGE, inode],
            capture_output=True, timeout=5
        )
        if icat_result.returncode == 0:
            data = icat_result.stdout
            size = len(data)
            md5 = hashlib.md5(data).hexdigest().lower()
            allocated_files.append({
                "name": name,
                "inode": inode,
                "size": size,
                "md5": md5
            })
    except Exception:
        pass

gt = {
    "image_path": IMAGE,
    "allocated_files": allocated_files,
    "total_allocated": len(allocated_files),
    "allocated_names": [f["name"] for f in allocated_files],
    "allocated_md5s": [f["md5"] for f in allocated_files]
}

with open("/tmp/ediscovery_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {len(allocated_files)} allocated user files found")
for f in allocated_files[:5]:
    print(f"  {f['name']} (MD5: {f['md5']})")
if len(allocated_files) > 5:
    print(f"  ... and {len(allocated_files) - 5} more.")
PYEOF

if [ ! -f /tmp/ediscovery_gt.json ]; then
    echo "WARNING: Ground truth computation failed"
    echo '{"allocated_files":[],"total_allocated":0,"allocated_names":[],"allocated_md5s":[]}' > /tmp/ediscovery_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/ediscovery_start_time

# ── Launch Autopsy ────────────────────────────────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy process to start..."
wait_for_autopsy_window 300

# Dismiss Welcome dialog if it appears
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        break
    fi
    sleep 3
done

# Focus Main Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Autopsy" | grep -vi "welcome" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take Initial Screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="