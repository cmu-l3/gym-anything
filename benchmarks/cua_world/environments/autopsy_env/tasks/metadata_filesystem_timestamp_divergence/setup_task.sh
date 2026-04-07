#!/bin/bash
# Setup script for metadata_filesystem_timestamp_divergence task

echo "=== Setting up Temporal Divergence Analysis task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/temporal_divergence_result.json /tmp/temporal_divergence_gt.json \
      /tmp/temporal_divergence_start_time 2>/dev/null || true

for d in /home/ga/Cases/Temporal_Divergence_2026*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/jpeg_search.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute Ground Truth (EXIF vs MTIME) ──────────────────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, sys, json, io, os
from datetime import datetime
try:
    from PIL import Image
except ImportError:
    print("WARNING: PIL not found, GT computation will be severely limited.")
    Image = None

image_path = "/home/ga/evidence/jpeg_search.dd"

gt_files = {}

# Use fls bodyfile format (mactime) to easily get mtime
try:
    proc = subprocess.run(["fls", "-r", "-m", "/", image_path], capture_output=True, text=True, timeout=60)
    lines = proc.stdout.splitlines()
except Exception as e:
    print("FLS Error:", e)
    lines = []

for line in lines:
    parts = line.split('|')
    if len(parts) < 11:
        continue
    
    name_part = parts[1].strip()
    inode_part = parts[2].strip()
    
    try:
        mtime_epoch = int(parts[8].strip())
    except ValueError:
        continue
        
    name = name_part.split('/')[-1].lower()
    
    if not (name.endswith('.jpg') or name.endswith('.jpeg')):
        continue
        
    inode = inode_part.split('-')[0]
    
    if Image is None:
        continue
        
    try:
        icat = subprocess.run(["icat", image_path, inode], capture_output=True, timeout=5)
        if icat.returncode == 0 and icat.stdout:
            img = Image.open(io.BytesIO(icat.stdout))
            exif = img._getexif()
            if exif:
                # 36867 = DateTimeOriginal, 306 = DateTime
                dt_str = exif.get(36867) or exif.get(306)
                if dt_str:
                    dt_str = str(dt_str).strip().replace('\x00', '')
                    # Format is usually "YYYY:MM:DD HH:MM:SS"
                    try:
                        exif_dt = datetime.strptime(dt_str, '%Y:%m:%d %H:%M:%S')
                        mtime_dt = datetime.fromtimestamp(mtime_epoch)
                        delta_days = abs((exif_dt - mtime_dt).days)
                        
                        gt_files[name] = {
                            "inode": inode,
                            "mtime": mtime_epoch,
                            "exif_date": dt_str,
                            "delta_days": delta_days
                        }
                    except ValueError:
                        pass
    except Exception:
        pass

with open("/tmp/temporal_divergence_gt.json", "w") as f:
    json.dump(gt_files, f, indent=2)

print(f"Ground truth computed: {len(gt_files)} JPEGs with EXIF dates found.")
for k, v in gt_files.items():
    print(f"  {k} -> delta: {v['delta_days']} days")

PYEOF

if [ ! -f /tmp/temporal_divergence_gt.json ]; then
    echo "WARNING: GT computation failed, creating empty GT"
    echo '{}' > /tmp/temporal_divergence_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/temporal_divergence_start_time
echo "Task start time recorded: $(cat /tmp/temporal_divergence_start_time)"

# ── Kill any running Autopsy and restart ──────────────────────────────────────
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
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
    kill_autopsy
    sleep 2
    launch_autopsy
    # Fallback tight loop
    for i in {1..24}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then break; fi
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        sleep 5
    done
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize Autopsy window
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Welcome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="