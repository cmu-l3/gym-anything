#!/bin/bash
echo "=== Setting up copy_session_identification task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/copy_session_result.json /tmp/copy_session_gt.json \
      /tmp/copy_session_start_time 2>/dev/null || true

for d in /home/ga/Cases/Copy_Session_Analysis_2024*/; do
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

# ── Pre-compute Ground Truth (Temporal Clustering) ────────────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, sys, os

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

# Use fls to output mactime format (md5|name|inode|mode|uid|gid|size|atime|mtime|ctime|crtime)
try:
    result = subprocess.run(
        ["fls", "-r", "-m", "", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

files = []
for line in lines:
    parts = line.split('|')
    if len(parts) < 11:
        continue
    
    name = parts[1].strip()
    mode = parts[3]
    
    # Extract file name without the full path
    basename = name.split('/')[-1] if '/' in name else name
    
    # Skip directories, system files, and alternate data streams
    if 'd' in mode:
        continue
    if basename in ['.', '..'] or basename.startswith('$') or ':' in basename:
        continue
        
    try:
        # TSK outputs epoch seconds for crtime
        crtime = int(parts[10])
        files.append({
            "name": basename,
            "crtime": crtime
        })
    except ValueError:
        pass

# Sort files chronologically
files.sort(key=lambda x: x["crtime"])

# Cluster into sessions (120-second window between consecutive files)
sessions = []
if files:
    current_session = [files[0]]
    for f in files[1:]:
        if f["crtime"] - current_session[-1]["crtime"] <= 120:
            current_session.append(f)
        else:
            sessions.append(current_session)
            current_session = [f]
    sessions.append(current_session)

total_files = len(files)
total_sessions = len(sessions)
largest_session = max((len(s) for s in sessions), default=0) if sessions else 0
all_names = [f["name"] for f in files]

gt = {
    "total_files": total_files,
    "total_sessions": total_sessions,
    "largest_session": largest_session,
    "file_names": all_names
}

with open("/tmp/copy_session_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {total_files} files in {total_sessions} sessions. Largest: {largest_session}")
PYEOF

if [ ! -f /tmp/copy_session_gt.json ]; then
    echo "WARNING: GT computation failed"
    echo '{"total_files":0,"total_sessions":0,"largest_session":0,"file_names":[]}' > /tmp/copy_session_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/copy_session_start_time

# ── Launch Autopsy ────────────────────────────────────────────────────────────
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
    echo "WARNING: Autopsy Welcome screen did not appear normally."
fi

# Dismiss any startup dialogs safely
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Autopsy window
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="