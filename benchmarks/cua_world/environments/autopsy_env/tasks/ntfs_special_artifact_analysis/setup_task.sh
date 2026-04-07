#!/bin/bash
# Setup script for ntfs_special_artifact_analysis task

echo "=== Setting up ntfs_special_artifact_analysis task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/ntfs_artifact_result.json /tmp/ntfs_artifact_gt.json \
      /tmp/ntfs_artifact_start_time 2>/dev/null || true

# Remove previous case directories for this task
for d in /home/ga/Cases/NTFS_Artifact_Analysis_2024*/; do
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
import subprocess, json, re, sys

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

def get_file_size(inode):
    try:
        res = subprocess.run(["istat", IMAGE, str(inode)], capture_output=True, text=True, timeout=10)
        m = re.search(r'Size:\s+(\d+)', res.stdout)
        if m:
            return int(m.group(1))
    except Exception:
        pass
    return 0

try:
    result = subprocess.run(
        ["fls", "-r", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

metafiles = []
orphan_files = []

# Autopsy virtual directory for orphans is $OrphanFiles
in_orphan_dir = False
orphan_indent = 0

for line in lines:
    stripped = re.sub(r'^[+\s]+', '', line)
    is_deleted = ' * ' in stripped
    
    # Check depth to track if we're inside $OrphanFiles
    depth = line.count('+')
    
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
        
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    
    if '\t' in name:
        name = name.split('\t')[0].strip()
        
    if name == '$OrphanFiles' and type_field.endswith('d'):
        in_orphan_dir = True
        orphan_indent = depth
        continue
        
    if in_orphan_dir and depth <= orphan_indent:
        in_orphan_dir = False
        
    if in_orphan_dir and not type_field.endswith('d') and name not in ('.', '..'):
        orphan_files.append({"name": name, "inode": inode, "deleted": is_deleted})
        
    # Standard metafiles (usually inode < 24 and starts with $)
    if name.startswith('$') and name not in ('.', '..', '$OrphanFiles'):
        # Ignore Alternate Data Streams and typical Windows dirs like $Recycle.Bin
        if ':' not in name and '$RECYCLE' not in name.upper() and type_field.endswith('r'):
            metafiles.append({"name": name, "inode": inode, "deleted": is_deleted})

# Deduplicate
meta_dict = {f["name"]: f for f in metafiles}
metafiles = list(meta_dict.values())

mft_size = get_file_size(0) # $MFT is always inode 0
logfile_size = get_file_size(2) # $LogFile is always inode 2

gt = {
    "image_path": IMAGE,
    "metafiles": metafiles,
    "metafile_names": [f["name"] for f in metafiles],
    "metafile_count": len(metafiles),
    "orphan_files": orphan_files,
    "orphan_names": [f["name"] for f in orphan_files],
    "orphan_count": len(orphan_files),
    "mft_size_bytes": mft_size,
    "logfile_size_bytes": logfile_size
}

with open("/tmp/ntfs_artifact_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth computed:")
print(f"  System Metafiles: {gt['metafile_count']}")
print(f"  Orphan Files: {gt['orphan_count']}")
print(f"  $MFT Size: {mft_size} bytes")
print(f"  $LogFile Size: {logfile_size} bytes")
PYEOF

if [ ! -f /tmp/ntfs_artifact_gt.json ]; then
    echo "WARNING: Ground truth computation failed, creating empty GT"
    echo '{"metafiles":[],"metafile_names":[],"metafile_count":0,"orphan_files":[],"orphan_names":[],"orphan_count":0,"mft_size_bytes":0,"logfile_size_bytes":0}' > /tmp/ntfs_artifact_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/ntfs_artifact_start_time

# ── Launch Autopsy and wait for Welcome screen ────────────────────────────────
echo "Launching Autopsy..."
kill_autopsy
sleep 2
launch_autopsy

echo "Waiting for Autopsy window..."
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
    echo "WARNING: Welcome screen not detected, continuing anyway..."
fi

# Maximize Autopsy window
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Autopsy" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="