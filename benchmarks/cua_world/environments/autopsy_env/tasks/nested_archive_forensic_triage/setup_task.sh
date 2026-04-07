#!/bin/bash
echo "=== Setting up nested_archive_forensic_triage task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up old artifacts
rm -f /tmp/nested_archive_result.json /tmp/nested_archive_gt.json /tmp/nested_archive_start_time 2>/dev/null || true
for d in /home/ga/Cases/Archive_Triage_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done
mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true
mkdir -p /home/ga/evidence

# 2. Generate the nested payload
echo "Generating nested archive payload..."
cd /tmp
rm -f payloads.zip server_backup.tar server_backup.dat vm_disk_01.dd usb_clone.dd 2>/dev/null || true

# Copy existing evidence images or create dummy ones if missing
cp /home/ga/evidence/ntfs_undel.dd /tmp/vm_disk_01.dd 2>/dev/null || dd if=/dev/urandom of=/tmp/vm_disk_01.dd bs=1M count=3
if [ -s "/home/ga/evidence/jpeg_search.dd" ]; then
    cp /home/ga/evidence/jpeg_search.dd /tmp/usb_clone.dd
else
    dd if=/dev/urandom of=/tmp/usb_clone.dd bs=1M count=2
fi

# Create nested container (ZIP inside GZIP Tarball)
python3 -c "import zipfile; zf = zipfile.ZipFile('payloads.zip', 'w', zipfile.ZIP_DEFLATED); zf.write('vm_disk_01.dd'); zf.write('usb_clone.dd'); zf.close()"
tar -czf /home/ga/evidence/server_backup.dat payloads.zip
chown ga:ga /home/ga/evidence/server_backup.dat

# 3. Compute ground truth MD5 hashes
python3 << 'PYEOF'
import hashlib, json
def get_md5(path):
    try:
        with open(path, 'rb') as f:
            return hashlib.md5(f.read()).hexdigest()
    except Exception:
        return ""

gt = {
    "server_backup.dat": get_md5("/home/ga/evidence/server_backup.dat"),
    "payloads.zip": get_md5("/tmp/payloads.zip"),
    "vm_disk_01.dd": get_md5("/tmp/vm_disk_01.dd"),
    "usb_clone.dd": get_md5("/tmp/usb_clone.dd")
}
with open("/tmp/nested_archive_gt.json", "w") as f:
    json.dump(gt, f, indent=2)
print("Ground truth hashes:")
for k, v in gt.items():
    print(f"  {k}: {v}")
PYEOF

date +%s > /tmp/nested_archive_start_time

# 4. Restart Autopsy and setup initial UI state
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false
while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected"
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy closed unexpectedly, relaunching..."
            launch_autopsy
        fi
    fi
done

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="