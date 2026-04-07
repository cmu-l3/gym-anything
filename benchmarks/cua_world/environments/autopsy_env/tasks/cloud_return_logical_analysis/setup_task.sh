#!/bin/bash
# Setup script for cloud_return_logical_analysis task

echo "=== Setting up cloud_return_logical_analysis task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/cloud_return_result.json /tmp/cloud_return_gt.json \
      /tmp/cloud_return_start_time 2>/dev/null || true

for d in /home/ga/Cases/Cloud_Return_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Prepare Logical Evidence Directory ────────────────────────────────────────
CLOUD_DIR="/home/ga/evidence/Cloud_Return"
rm -rf "$CLOUD_DIR" 2>/dev/null || true
mkdir -p "$CLOUD_DIR/USB_Backup"
mkdir -p "$CLOUD_DIR/Camera_Uploads"

IMAGE1="/home/ga/evidence/ntfs_undel.dd"
IMAGE2="/home/ga/evidence/jpeg_search.dd"

echo "Extracting logical files from disk images to simulate a cloud return..."
if command -v tsk_recover >/dev/null 2>&1; then
    [ -s "$IMAGE1" ] && tsk_recover "$IMAGE1" "$CLOUD_DIR/USB_Backup" 2>/dev/null || true
    [ -s "$IMAGE2" ] && tsk_recover "$IMAGE2" "$CLOUD_DIR/Camera_Uploads" 2>/dev/null || true
else
    echo "WARNING: tsk_recover not found. Using fallback files."
    cp /etc/hosts "$CLOUD_DIR/USB_Backup/hosts.txt" 2>/dev/null || true
    echo "Sample text file" > "$CLOUD_DIR/USB_Backup/sample.txt"
fi

# Set ownership
chown -R ga:ga "$CLOUD_DIR" 2>/dev/null || true

# ── Pre-compute Physical Ground Truth ─────────────────────────────────────────
echo "Computing physical ground truth from extracted files..."
python3 << 'PYEOF'
import os, hashlib, json, subprocess

gt = {
    "total_files_extracted": 0,
    "jpeg_count": 0,
    "text_count": 0,
    "extracted_files": []
}

base_dir = "/home/ga/evidence/Cloud_Return"

if os.path.exists(base_dir):
    for root, dirs, files in os.walk(base_dir):
        for f in files:
            path = os.path.join(root, f)
            try:
                # Basic size and hash
                with open(path, "rb") as fh:
                    data = fh.read()
                    md5 = hashlib.md5(data).hexdigest()
                    size = len(data)
                
                # Best-effort MIME type using 'file' command
                try:
                    mime = subprocess.check_output(["file", "--mime-type", "-b", path]).decode().strip()
                except Exception:
                    mime = "unknown"
                
                gt["extracted_files"].append({
                    "name": f,
                    "path": path,
                    "md5": md5,
                    "mime": mime,
                    "size": size
                })
                
                gt["total_files_extracted"] += 1
                if "jpeg" in mime:
                    gt["jpeg_count"] += 1
                if "text" in mime:
                    gt["text_count"] += 1
            except Exception:
                pass

with open("/tmp/cloud_return_gt.json", "w") as fh:
    json.dump(gt, fh, indent=2)

print(f"Extracted GT: {gt['total_files_extracted']} total files, {gt['jpeg_count']} JPEGs, {gt['text_count']} Text files")
PYEOF

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/cloud_return_start_time

# ── Launch Autopsy ────────────────────────────────────────────────────────────
kill_autopsy
sleep 2

echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

# Dismiss welcome screens quickly
for i in {1..15}; do
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 2
done

take_screenshot /tmp/task_initial_state.png ga
echo "=== Task Setup Complete ==="