#!/bin/bash
# Setup script for deleted_evidence_recovery task
# Do NOT use set -e — individual failures are handled explicitly

echo "=== Setting up deleted_evidence_recovery task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/deleted_evidence_result.json /tmp/deleted_evidence_gt.json \
      /tmp/deleted_evidence_start_time 2>/dev/null || true

# Remove previous case directories for this task
for d in /home/ga/Cases/Deleted_Evidence_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

# Create report output directories
mkdir -p /home/ga/Reports/deleted_evidence
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth (deleted files) ──────────────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, sys

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

try:
    result = subprocess.run(
        ["fls", "-r", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

deleted_files = []
for line in lines:
    # fls output format:
    #   Allocated:  "r/r INODE: NAME"
    #   Deleted:    "-/r * INODE: NAME"  OR  "r/r * INODE: NAME"
    #   Nested:     "+ -/r * INODE: NAME"  OR  "++ -/r * INODE: NAME"
    # Must handle both '-/r' (unalloc dir-entry) and 'r/r' (alloc dir-entry but deleted meta)
    if ' * ' not in line:
        continue
    # Strip leading depth indicators (+ symbols and spaces)
    stripped = re.sub(r'^[+\s]+', '', line)
    # Match: TYPE * INODE[-seq[-attr]]: NAME
    m = re.match(r'^([\w/-]+)\s+\*\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    # Handle tab-separated name (take only the name part)
    if '\t' in name:
        name = name.split('\t')[0].strip()
    # Skip directories (type ends in d)
    if type_field.endswith('d'):
        continue
    # Skip system/metadata files
    if name in ('.', '..'):
        continue
    if name.startswith('$') and name not in ('$Recycle.Bin', '$RECYCLE.BIN'):
        continue
    # Skip Alternate Data Streams (name contains colon)
    if ':' in name:
        continue
    deleted_files.append({"name": name, "inode": inode})

gt = {
    "deleted_files": deleted_files,
    "total_deleted": len(deleted_files),
    "image_path": IMAGE,
    "deleted_names": [f["name"] for f in deleted_files]
}
with open("/tmp/deleted_evidence_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {len(deleted_files)} deleted files found")
for f in deleted_files:
    print(f"  inode={f['inode']}: {f['name']}")
PYEOF

if [ ! -f /tmp/deleted_evidence_gt.json ]; then
    echo "WARNING: Ground truth computation failed, creating empty GT"
    echo '{"deleted_files":[],"total_deleted":0,"deleted_names":[]}' > /tmp/deleted_evidence_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/deleted_evidence_start_time
echo "Task start time recorded: $(cat /tmp/deleted_evidence_start_time)"

# ── Kill any running Autopsy ──────────────────────────────────────────────────
kill_autopsy

# ── Launch Autopsy and wait for Welcome screen ────────────────────────────────
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
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 5
        FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
    if [ "$WELCOME_FOUND" = false ]; then
        echo "FATAL: Welcome screen never appeared."
        exit 1
    fi
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
    echo "VERIFIED: Autopsy Welcome screen is visible and ready"
else
    echo "WARNING: Welcome screen may have been dismissed. Current windows:"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
fi

echo "=== Task setup complete ==="
echo "GT deleted files: $(python3 -c "import json; d=json.load(open('/tmp/deleted_evidence_gt.json')); print(d['total_deleted'])" 2>/dev/null || echo '?')"
