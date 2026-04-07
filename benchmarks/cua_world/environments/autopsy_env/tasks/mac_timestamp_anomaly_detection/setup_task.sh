#!/bin/bash
# Setup script for mac_timestamp_anomaly_detection task
echo "=== Setting up mac_timestamp_anomaly_detection task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/mac_anomaly_result.json /tmp/mac_anomaly_gt.json \
      /tmp/mac_anomaly_start_time 2>/dev/null || true

for d in /home/ga/Cases/Timestamp_Anomaly_2024*/; do
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

# ── Pre-compute Ground Truth (Timestamps and Anomalies) ───────────────────────
echo "Pre-computing ground truth for MAC timestamps from TSK..."
python3 << 'PYEOF'
import subprocess, json, sys, re

IMAGE = "/home/ga/evidence/ntfs_undel.dd"
DATE_FUTURE_CUTOFF = 1705276800  # 2024-01-15 00:00:00 UTC
DATE_PAST_CUTOFF = 946684800     # 2000-01-01 00:00:00 UTC

try:
    # Use fls to generate a bodyfile to easily parse MAC times
    result = subprocess.run(
        ["fls", "-m", "/", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    bodyfile_lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls -m failed: {e}")
    bodyfile_lines = []

total_files = 0
total_allocated = 0
total_deleted = 0
filenames = []

anomaly_created_after_modified = 0
anomaly_future = 0
anomaly_pre_2000 = 0

min_time = 2000000000
max_time = 0

for line in bodyfile_lines:
    parts = line.split('|')
    if len(parts) < 11:
        continue
    
    # Bodyfile format: MD5|name|inode|mode|UID|GID|size|atime|mtime|ctime|crtime
    name = parts[1].strip()
    
    # Skip directories and specials
    if parts[3].startswith('d') or parts[3].startswith('v'):
        continue
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue

    is_deleted = '(deleted)' in name
    if is_deleted:
        total_deleted += 1
        clean_name = name.replace(' (deleted)', '')
    else:
        total_allocated += 1
        clean_name = name

    total_files += 1
    filenames.append(clean_name)

    try:
        atime = int(parts[7])
        mtime = int(parts[8])
        ctime = int(parts[9])
        crtime = int(parts[10])
        
        times = [t for t in (atime, mtime, ctime, crtime) if t > 0]
        if times:
            file_min = min(times)
            file_max = max(times)
            if file_min < min_time: min_time = file_min
            if file_max > max_time: max_time = file_max

        # Check anomalies
        if crtime > 0 and mtime > 0 and crtime > mtime:
            anomaly_created_after_modified += 1
            
        if any(t > DATE_FUTURE_CUTOFF for t in times):
            anomaly_future += 1
            
        if any(0 < t < DATE_PAST_CUTOFF for t in times):
            anomaly_pre_2000 += 1

    except ValueError:
        pass

# Convert min/max to approx ISO dates for comparison bounds
import datetime
try:
    earliest_date = datetime.datetime.utcfromtimestamp(min_time).strftime('%Y-%m-%d')
except:
    earliest_date = "1970-01-01"

try:
    latest_date = datetime.datetime.utcfromtimestamp(max_time).strftime('%Y-%m-%d')
except:
    latest_date = "2030-01-01"

gt = {
    "total_files": total_files,
    "total_allocated": total_allocated,
    "total_deleted": total_deleted,
    "anomaly_created_after_modified": anomaly_created_after_modified,
    "anomaly_future_timestamps": anomaly_future,
    "anomaly_pre_2000_timestamps": anomaly_pre_2000,
    "earliest_date": earliest_date,
    "latest_date": latest_date,
    "filenames": filenames
}

with open("/tmp/mac_anomaly_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth computed:")
print(f"  Total Files: {total_files} (Alloc: {total_allocated}, Del: {total_deleted})")
print(f"  Anomalies -> Cr>Mod: {anomaly_created_after_modified}, Future: {anomaly_future}, Pre-2000: {anomaly_pre_2000}")
print(f"  Window -> {earliest_date} to {latest_date}")
PYEOF

if [ ! -f /tmp/mac_anomaly_gt.json ]; then
    echo "WARNING: Ground truth computation failed, creating dummy GT"
    echo '{"total_files":0}' > /tmp/mac_anomaly_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/mac_anomaly_start_time

# ── Kill any running Autopsy and relaunch ─────────────────────────────────────
kill_autopsy

echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

# Wait for Welcome Screen
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
    echo "ERROR: Autopsy Welcome screen did NOT appear."
    kill_autopsy; sleep 2; launch_autopsy
    sleep 30
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "welcome" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="