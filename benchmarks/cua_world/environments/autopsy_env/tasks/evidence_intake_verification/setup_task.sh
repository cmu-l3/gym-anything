#!/bin/bash
# Setup script for evidence_intake_verification task

echo "=== Setting up evidence_intake_verification task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up stale artifacts
rm -f /tmp/evidence_intake_result.json /tmp/evidence_intake_gt.json \
      /tmp/task_start_time.txt 2>/dev/null || true

for d in /home/ga/Cases/Evidence_Intake_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
rm -f /home/ga/Reports/intake_report.txt /home/ga/Reports/file_inventory.csv
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# 2. Verify disk image
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# 3. Pre-compute ground truth from image content
echo "Pre-computing ground truth..."
python3 << 'PYEOF'
import subprocess, json, re, os, hashlib

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

# Image MD5
with open(IMAGE, "rb") as f:
    file_hash = hashlib.md5()
    while chunk := f.read(8192):
        file_hash.update(chunk)
image_md5 = file_hash.hexdigest()

# Image size
image_size = os.path.getsize(IMAGE)

# File system type
fs_type = "UNKNOWN"
try:
    fsstat_res = subprocess.run(["fsstat", IMAGE], capture_output=True, text=True, timeout=10)
    for line in fsstat_res.stdout.splitlines():
        if "File System Type:" in line:
            fs_type = line.split("Type:")[1].strip()
            break
except Exception as e:
    print(f"WARNING: fsstat failed: {e}")

# File counts (fls -r -F for files, -D for directories)
try:
    fls_f = subprocess.run(["fls", "-r", "-F", IMAGE], capture_output=True, text=True, timeout=30)
    fls_f_lines = fls_f.stdout.splitlines()
    total_files = len(fls_f_lines)
    deleted_files = sum(1 for line in fls_f_lines if ' * ' in line)
    allocated_files = total_files - deleted_files
    
    # Filenames for inventory coverage check
    file_names = []
    for line in fls_f_lines:
        stripped = re.sub(r'^[+\s]+', '', line)
        m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
        if m:
            name = m.group(3).strip()
            if '\t' in name:
                name = name.split('\t')[0].strip()
            if name not in ('.', '..') and not name.startswith('$'):
                file_names.append(name)
except Exception as e:
    print(f"WARNING: fls files failed: {e}")
    total_files = allocated_files = deleted_files = 0
    file_names = []

try:
    fls_d = subprocess.run(["fls", "-r", "-D", IMAGE], capture_output=True, text=True, timeout=30)
    total_directories = len(fls_d.stdout.splitlines())
except Exception as e:
    print(f"WARNING: fls dirs failed: {e}")
    total_directories = 0

gt = {
    "image_md5": image_md5,
    "image_size": image_size,
    "fs_type": fs_type,
    "total_files": total_files,
    "deleted_files": deleted_files,
    "allocated_files": allocated_files,
    "total_directories": total_directories,
    "file_names": file_names
}

with open("/tmp/evidence_intake_gt.json", "w") as f:
    json.dump(gt, f, indent=2)
print(f"Computed GT: {total_files} files, {total_directories} directories. MD5: {image_md5}")
PYEOF

date +%s > /tmp/task_start_time.txt

# 4. Launch Autopsy safely
kill_autopsy
launch_autopsy
wait_for_autopsy_window 300

# Dismiss welcome screen nudges robustly
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
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="