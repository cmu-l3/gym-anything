#!/bin/bash
# Setup script for warrant_constrained_logical_triage task

echo "=== Setting up warrant_constrained_logical_triage task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Clean up stale artifacts ────────────────────────────────────────────────
rm -f /tmp/warrant_constrained_result.json /tmp/warrant_constrained_start_time 2>/dev/null || true
rm -rf /home/ga/evidence/constrained_export 2>/dev/null || true

for d in /home/ga/Cases/Constrained_Warrant_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── 2. Verify disk image exists ────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── 3. Record task start time ──────────────────────────────────────────────────
date +%s > /tmp/warrant_constrained_start_time

# ── 4. Manage Autopsy Environment ──────────────────────────────────────────────
kill_autopsy
sleep 2

echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy Welcome screen..."
wait_for_autopsy_window 300

# Basic click-through to ensure UI is ready
WELCOME_TIMEOUT=120
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected"
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga
echo "Captured initial screenshot."

echo "=== Task setup complete ==="