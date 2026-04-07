#!/bin/bash
# Setup script for portable_case_generation task

echo "=== Setting up portable_case_generation task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up stale artifacts to ensure a fresh environment
rm -f /tmp/portable_case_result.json /tmp/portable_case_start_time 2>/dev/null || true

echo "Cleaning up old case directories..."
for d in /home/ga/Cases/Evidence_Handover_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

# Clean up portable cases that might have been exported elsewhere
find /home/ga/Cases /home/ga/Reports /home/ga/Documents -type d -name "*Portable*" -exec rm -rf {} + 2>/dev/null || true

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# 2. Verify disk image exists
IMAGE="/home/ga/evidence/jpeg_search.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image verified: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# 3. Record task start time (used to prevent gaming file timestamps)
date +%s > /tmp/portable_case_start_time
echo "Task start time recorded: $(cat /tmp/portable_case_start_time)"

# 4. Launch Autopsy and wait for the Welcome screen
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy process to initialize..."
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
    # Click center of screen to dismiss any non-focused splash popups
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    
    # Relaunch if the process unexpectedly died
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy died, relaunching at ${WELCOME_ELAPSED}s..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
    # Fallback attempt
    kill_autopsy; sleep 2; launch_autopsy
    sleep 30
fi

# Ensure window is maximized
WID=$(DISPLAY=:1 wmctrl -l | grep -i "autopsy\|welcome" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="