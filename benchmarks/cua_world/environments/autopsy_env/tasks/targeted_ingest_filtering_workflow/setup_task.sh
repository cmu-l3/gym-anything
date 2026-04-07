#!/bin/bash
# Setup script for targeted_ingest_filtering_workflow task

echo "=== Setting up targeted_ingest_filtering_workflow task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/targeted_ingest_result.json /tmp/targeted_ingest_start_time 2>/dev/null || true

for d in /home/ga/Cases/Targeted_Ingest_2024*/; do
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

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/targeted_ingest_start_time

# ── Launch Autopsy and wait for Welcome screen ────────────────────────────────
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
    exit 1
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

take_screenshot /tmp/targeted_ingest_initial.png ga
echo "=== Task setup complete ==="