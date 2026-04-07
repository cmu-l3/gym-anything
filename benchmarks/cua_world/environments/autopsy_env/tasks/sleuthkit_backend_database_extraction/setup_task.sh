#!/bin/bash
# Setup script for sleuthkit_backend_database_extraction task

echo "=== Setting up sleuthkit_backend_database_extraction task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up stale artifacts from previous runs
rm -f /tmp/sleuthkit_backend_result.json /tmp/sleuthkit_backend_start_time 2>/dev/null || true

for d in /home/ga/Cases/Backend_DB_Extraction_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case directory: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true
rm -f /home/ga/Reports/custom_hash_export.csv 2>/dev/null || true

# 2. Verify evidence disk image exists
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image verified: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# 3. Record task start time for anti-gaming verification
date +%s > /tmp/sleuthkit_backend_start_time
echo "Task start time recorded: $(cat /tmp/sleuthkit_backend_start_time)"

# 4. Ensure a clean Autopsy launch
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy GUI to appear..."
wait_for_autopsy_window 300

# Handle Autopsy's Welcome screen to ensure the agent has a clear starting state
WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected after ${WELCOME_ELAPSED}s"
        WELCOME_FOUND=true
        break
    fi
    # Click to bypass any splash screen hangs
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy process died, relaunching..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "WARNING: Welcome screen did not appear, proceeding anyway."
fi

# Dismiss any lingering popups just in case
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Autopsy window
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take an initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
echo "=== Setup complete ==="