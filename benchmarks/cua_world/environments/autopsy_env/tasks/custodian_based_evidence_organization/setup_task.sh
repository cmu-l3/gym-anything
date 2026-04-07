#!/bin/bash
# Setup script for custodian_based_evidence_organization task

echo "=== Setting up custodian_based_evidence_organization task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/custodian_result.json /tmp/custodian_start_time 2>/dev/null || true

for d in /home/ga/Cases/Custodian_Tracking_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk images ────────────────────────────────────────────────────────
IMAGE1="/home/ga/evidence/ntfs_undel.dd"
IMAGE2="/home/ga/evidence/jpeg_search.dd"

# Ensure at least placeholder files exist if the real downloads failed previously
if [ ! -s "$IMAGE1" ]; then
    echo "Creating fallback for $IMAGE1"
    mkdir -p /home/ga/evidence
    dd if=/dev/zero of="$IMAGE1" bs=1M count=5 2>/dev/null
    mkfs.fat -F 32 "$IMAGE1" 2>/dev/null || true
fi

if [ ! -s "$IMAGE2" ]; then
    echo "Creating fallback for $IMAGE2"
    mkdir -p /home/ga/evidence
    dd if=/dev/zero of="$IMAGE2" bs=1M count=5 2>/dev/null
    mkfs.fat -F 32 "$IMAGE2" 2>/dev/null || true
fi

echo "Disk image 1: $IMAGE1 ($(stat -c%s "$IMAGE1") bytes)"
echo "Disk image 2: $IMAGE2 ($(stat -c%s "$IMAGE2") bytes)"
chown -R ga:ga /home/ga/evidence 2>/dev/null || true

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/custodian_start_time

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
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy died, relaunching..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "FATAL: Welcome screen never appeared."
    # We still exit 0 so the agent can at least try or fail gracefully
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take an initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup Complete ==="