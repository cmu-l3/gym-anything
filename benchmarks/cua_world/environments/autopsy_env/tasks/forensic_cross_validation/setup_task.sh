#!/bin/bash
# Setup script for forensic_cross_validation task

echo "=== Setting up forensic_cross_validation task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/crossval_result.json /tmp/crossval_gt.json \
      /tmp/crossval_start_time 2>/dev/null || true

for d in /home/ga/Cases/QA_Crossval_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

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
import subprocess, json, re, hashlib, sys

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

gt = {
    "total_files": 0,
    "allocated_files": 0,
    "deleted_files": 0,
    "hashes": {},
    "sector_size": ""
}

try:
    img_out = subprocess.check_output(["img_stat", IMAGE], text=True, timeout=10)
    m = re.search(r'Sector Size:\s+(\d+)', img_out)
    if m: gt["sector_size"] = m.group(1)
except Exception as e:
    print(f"img_stat failed: {e}")

try:
    fls_out = subprocess.check_output(["fls", "-r", "-l", "-p", IMAGE], text=True, timeout=30)
    files = []
    for line in fls_out.splitlines():
        line = re.sub(r'^[+\s]+', '', line)
        m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', line)
        if m:
            type_str = m.group(1)
            inode = m.group(2)
            path = m.group(3).strip()
            is_deleted = '*' in line
            if type_str.endswith('r') or type_str.endswith('d'):
                files.append({"inode": inode, "path": path, "deleted": is_deleted})
    
    gt["total_files"] = len(files)
    allocated = [f for f in files if not f["deleted"]]
    gt["allocated_files"] = len(allocated)
    gt["deleted_files"] = gt["total_files"] - gt["allocated_files"]
    
    # Hash some allocated files for ground truth
    for f in allocated[:40]:
        try:
            icat = subprocess.check_output(["icat", IMAGE, f["inode"]], timeout=2)
            if icat:
                gt["hashes"][f["inode"]] = hashlib.md5(icat).hexdigest()
        except Exception:
            pass
except Exception as e:
    print(f"fls failed: {e}")

with open("/tmp/crossval_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {gt['total_files']} files ({gt['allocated_files']} alloc, {gt['deleted_files']} deleted)")
print(f"Hashed {len(gt['hashes'])} files for validation.")
PYEOF

if [ ! -f /tmp/crossval_gt.json ]; then
    echo "WARNING: Ground truth computation failed, creating empty GT"
    echo '{"total_files":0,"allocated_files":0,"deleted_files":0,"hashes":{}}' > /tmp/crossval_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/crossval_start_time
echo "Task start time recorded: $(cat /tmp/crossval_start_time)"

# ── Launch Autopsy and wait for Welcome screen ────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
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
            WELCOME_FOUND=true
            break
        fi
        sleep 5; FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# ── Take initial screenshot ───────────────────────────────────────────────────
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="