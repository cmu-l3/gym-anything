#!/bin/bash
# Setup script for ediscovery_bates_production_workflow task

echo "=== Setting up E-Discovery Bates Production task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/ediscovery_result.json /tmp/ediscovery_gt.json \
      /tmp/ediscovery_start_time /tmp/task_initial.png 2>/dev/null || true

for d in /home/ga/Cases/EDiscovery_Smith_v_Corp*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

rm -rf /home/ga/Reports/Production 2>/dev/null || true
mkdir -p /home/ga/Reports/Production/raw
mkdir -p /home/ga/Reports/Production/bates
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth (.txt files) ─────────────────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, hashlib, sys

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

try:
    result = subprocess.run(["fls", "-r", IMAGE], capture_output=True, text=True, timeout=60)
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

txt_files = []
for line in lines:
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

    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue

    if name.lower().endswith('.txt'):
        try:
            icat_result = subprocess.run(["icat", IMAGE, inode], capture_output=True, timeout=5)
            if icat_result.returncode == 0:
                content = icat_result.stdout
                txt_files.append({
                    "name": name,
                    "inode": inode,
                    "deleted": is_deleted,
                    "md5": hashlib.md5(content).hexdigest(),
                    "size": len(content)
                })
        except Exception as e:
            pass

gt = {
    "txt_files": txt_files,
    "total_txt": len(txt_files),
    "txt_hashes": [f["md5"] for f in txt_files]
}
with open("/tmp/ediscovery_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {gt['total_txt']} .txt files found")
PYEOF

if [ ! -f /tmp/ediscovery_gt.json ]; then
    echo "WARNING: Ground truth computation failed, creating empty GT"
    echo '{"txt_files":[],"total_txt":0,"txt_hashes":[]}' > /tmp/ediscovery_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/ediscovery_start_time

# ── Launch Autopsy and wait for Welcome screen ────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy process to start..."
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
            echo "Autopsy died, relaunching at ${WELCOME_ELAPSED}s..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
    kill_autopsy
    sleep 2
    launch_autopsy
    FINAL_ELAPSED=0
    while [ $FINAL_ELAPSED -lt 120 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
            echo "Welcome screen appeared on retry after additional ${FINAL_ELAPSED}s"
            WELCOME_FOUND=true
            break
        fi
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        sleep 5
        FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="