#!/bin/bash
# Setup script for intra_device_duplicate_analysis task

echo "=== Setting up intra_device_duplicate_analysis task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/duplicate_analysis_result.json /tmp/duplicate_analysis_gt.json \
      /tmp/duplicate_analysis_start_time 2>/dev/null || true

# Remove previous case directories for this task
for d in /home/ga/Cases/Duplicate_Analysis_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

# Create report output directories
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
import subprocess, json, re, hashlib, collections

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
    if ' * ' in line:
        continue # skip deleted
    stripped = re.sub(r'^[+\s]+', '', line)
    
    m = re.match(r'^([\w/-]+)\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
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
        
    allocated_files.append({"name": name, "inode": inode})

# Compute hashes and file sizes
file_hashes = {}
nonzero_allocated = 0

for f in allocated_files:
    try:
        icat_result = subprocess.run(
            ["icat", IMAGE, f["inode"]],
            capture_output=True, timeout=10
        )
        data = icat_result.stdout
        if len(data) > 0:
            md5 = hashlib.md5(data).hexdigest()
            # Store grouped by MD5
            if md5 not in file_hashes:
                file_hashes[md5] = []
            file_hashes[md5].append(f["name"])
            nonzero_allocated += 1
    except Exception:
        pass

# Filter to duplicates
duplicate_groups = {md5: names for md5, names in file_hashes.items() if len(names) >= 2}

gt = {
    "total_nonzero_allocated": nonzero_allocated,
    "total_unique_hashes": len(file_hashes),
    "total_duplicate_groups": len(duplicate_groups),
    "duplicate_groups": duplicate_groups,
    "image_path": IMAGE
}

with open("/tmp/duplicate_analysis_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth computed:")
print(f"  Total nonzero allocated files: {nonzero_allocated}")
print(f"  Total unique hashes: {len(file_hashes)}")
print(f"  Total duplicate groups: {len(duplicate_groups)}")
for md5, names in duplicate_groups.items():
    print(f"    {md5}: {len(names)} copies -> {', '.join(names[:2])}...")
PYEOF

if [ ! -f /tmp/duplicate_analysis_gt.json ]; then
    echo "WARNING: Ground truth computation failed."
    echo '{"total_nonzero_allocated":0,"total_unique_hashes":0,"total_duplicate_groups":0,"duplicate_groups":{}}' > /tmp/duplicate_analysis_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/duplicate_analysis_start_time

# ── Kill any running Autopsy ──────────────────────────────────────────────────
kill_autopsy
sleep 2

# ── Launch Autopsy and wait for Welcome screen ────────────────────────────────
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy window..."
wait_for_autopsy_window 300

# Dismiss any stray dialogs and capture initial state
sleep 15
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Autopsy window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "autopsy" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="