#!/bin/bash
# Setup script for evidence_extraction_packaging task

echo "=== Setting up evidence_extraction_packaging task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/evidence_extraction_result.json /tmp/evidence_extraction_gt.json \
      /tmp/evidence_extraction_start_time 2>/dev/null || true

for d in /home/ga/Cases/Evidence_Packaging_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports/extracted_evidence
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth (File Hashes) ────────────────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, hashlib, os

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

def hash_file(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            h.update(chunk)
    return h.hexdigest()

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
for line in lines:
    if ' * ' not in line and 'r/r' not in line and '-/r' not in line:
        continue
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
        
    # Skip directories
    if type_field.endswith('d'):
        continue
        
    # Skip NTFS metadata files
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue
        
    files.append({
        "name": name,
        "inode": inode,
        "deleted": is_deleted
    })

gt_files = []
allocated_count = 0
deleted_count = 0

for f in files:
    try:
        icat = subprocess.run(
            ["icat", IMAGE, f["inode"]],
            capture_output=True, timeout=5
        )
        if icat.returncode == 0:
            content = icat.stdout
            md5 = hashlib.md5(content).hexdigest()
            sha256 = hashlib.sha256(content).hexdigest()
            
            gt_files.append({
                "name": f["name"],
                "inode": f["inode"],
                "deleted": f["deleted"],
                "size": len(content),
                "md5": md5,
                "sha256": sha256
            })
            if f["deleted"]:
                deleted_count += 1
            else:
                allocated_count += 1
    except Exception:
        pass

gt = {
    "image_path": IMAGE,
    "image_md5": hash_file(IMAGE),
    "total_regular_files": len(gt_files),
    "allocated_count": allocated_count,
    "deleted_count": deleted_count,
    "files": gt_files,
    "md5_set": [f["md5"] for f in gt_files],
    "sha256_set": [f["sha256"] for f in gt_files]
}

with open("/tmp/evidence_extraction_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {len(gt_files)} regular files found, Image MD5: {gt['image_md5']}")
PYEOF

if [ ! -f /tmp/evidence_extraction_gt.json ]; then
    echo "WARNING: GT computation failed"
    echo '{"total_regular_files":0,"files":[],"md5_set":[],"image_md5":""}' > /tmp/evidence_extraction_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/evidence_extraction_start_time

# ── Kill Autopsy and relaunch ─────────────────────────────────────────────────
kill_autopsy

echo "Launching Autopsy..."
launch_autopsy
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
    kill_autopsy; sleep 2; launch_autopsy
    FINAL_ELAPSED=0
    while [ $FINAL_ELAPSED -lt 120 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
            WELCOME_FOUND=true; break
        fi
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        sleep 5; FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="