#!/bin/bash
# Setup script for exif_metadata_provenance task

echo "=== Setting up exif_metadata_provenance task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/exif_provenance_result.json /tmp/exif_provenance_gt.json \
      /tmp/exif_provenance_start_time 2>/dev/null || true

for d in /home/ga/Cases/Photo_Provenance_2024*/; do
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

# ── Pre-compute TSK ground truth (EXIF metadata via PIL) ─────────────────────
echo "Pre-computing ground truth from TSK (EXIF parsing)..."
python3 << 'PYEOF'
import subprocess, json, re, sys, io
from PIL import Image, ExifTags

IMAGE = "/home/ga/evidence/jpeg_search.dd"

try:
    result = subprocess.run(
        ["fls", "-r", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

image_files = []
img_exts = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".jfif"}

for line in lines:
    stripped = re.sub(r'^[+\s]+', '', line)
    is_deleted = ' * ' in stripped
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m: continue
    
    type_field, inode, name = m.group(1), m.group(2), m.group(3).strip()
    if '\t' in name: name = name.split('\t')[0].strip()
    
    if type_field.endswith('d') or type_field.endswith('v'): continue
    if name in ('.', '..') or name.startswith('$') or ':' in name: continue
    
    ext = name[name.rfind('.'):].lower() if '.' in name else ""
    if ext in img_exts:
        # Extract file with icat and parse EXIF
        has_exif = False
        camera_make = "NONE"
        camera_model = "NONE"
        date_taken = "NONE"
        gps = False
        size = 0
        
        try:
            icat = subprocess.run(["icat", IMAGE, inode], capture_output=True, timeout=10)
            if icat.returncode == 0:
                img_bytes = icat.stdout
                size = len(img_bytes)
                if size > 0:
                    try:
                        img = Image.open(io.BytesIO(img_bytes))
                        exif = img._getexif()
                        if exif:
                            has_exif = True
                            # 271=Make, 272=Model, 306=DateTime, 34853=GPSInfo
                            camera_make = str(exif.get(271, "NONE")).strip().replace('\x00', '')
                            camera_model = str(exif.get(272, "NONE")).strip().replace('\x00', '')
                            date_taken = str(exif.get(306, "NONE")).strip()
                            gps = 34853 in exif
                    except Exception:
                        pass
        except Exception:
            pass
            
        if camera_make == "None" or not camera_make: camera_make = "NONE"
        if camera_model == "None" or not camera_model: camera_model = "NONE"
        if date_taken == "None" or not date_taken: date_taken = "NONE"

        image_files.append({
            "name": name,
            "inode": inode,
            "deleted": is_deleted,
            "size": size,
            "has_exif": has_exif,
            "make": camera_make,
            "model": camera_model,
            "date": date_taken,
            "has_gps": gps
        })

exif_files = [f for f in image_files if f["has_exif"]]
cameras = list(set([f"{f['make']} {f['model']}".strip() for f in exif_files if f['make'] != 'NONE']))

gt = {
    "total_image_files": len(image_files),
    "images_with_exif": len(exif_files),
    "images_without_exif": len(image_files) - len(exif_files),
    "images_with_gps": sum(1 for f in image_files if f["has_gps"]),
    "unique_cameras": cameras,
    "unique_cameras_count": len(cameras),
    "image_names": [f["name"] for f in image_files],
    "image_path": IMAGE
}

with open("/tmp/exif_provenance_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {gt['total_image_files']} images found, {gt['images_with_exif']} with EXIF.")
PYEOF

if [ ! -f /tmp/exif_provenance_gt.json ]; then
    echo "WARNING: GT computation failed"
    echo '{"total_image_files":0}' > /tmp/exif_provenance_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/exif_provenance_start_time

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
done

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Autopsy" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="