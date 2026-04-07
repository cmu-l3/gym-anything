#!/bin/bash
# Do NOT use set -e: individual command failures are handled explicitly below

echo "=== Setting up examine_file_metadata task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Clean up any leftover temp files from previous tasks
rm -f /tmp/initial_* /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

# ============================================================
# Verify disk image exists and is readable
# ============================================================
DISK_IMAGE="/home/ga/evidence/jpeg_search.dd"

if [ ! -s "$DISK_IMAGE" ]; then
    echo "WARNING: Primary disk image not found, checking alternatives..."
    for alt in /home/ga/evidence/*.dd; do
        if [ -s "$alt" ]; then
            DISK_IMAGE="$alt"
            echo "Using alternative image: $DISK_IMAGE"
            break
        fi
    done
fi

if [ ! -s "$DISK_IMAGE" ]; then
    echo "ERROR: No disk image found in /home/ga/evidence/"
    exit 1
fi

echo "Disk image: $DISK_IMAGE ($(stat -c%s "$DISK_IMAGE") bytes)"

# Record initial state for verification
echo "$DISK_IMAGE" > /tmp/initial_disk_image_path

# Use TSK to pre-analyze the image for ground truth
echo "Pre-analyzing disk image with TSK..."
if command -v fls >/dev/null 2>&1; then
    FILE_COUNT=$(fls -r "$DISK_IMAGE" 2>/dev/null | wc -l)
    echo "Files found by TSK: $FILE_COUNT"
    echo "$FILE_COUNT" > /tmp/initial_file_count

    # List some files for reference
    fls -r "$DISK_IMAGE" 2>/dev/null | head -20 > /tmp/initial_file_listing
fi

# ============================================================
# Kill any running Autopsy instances
# ============================================================
kill_autopsy

# ============================================================
# Launch Autopsy and BLOCK until Welcome screen is confirmed
# ============================================================
echo "Launching Autopsy..."
launch_autopsy

# Phase 1: Wait for ANY Autopsy window to appear (splash, main, or welcome)
echo "Waiting for Autopsy process to start..."
wait_for_autopsy_window 300

# Phase 2: Nudge splash screen and BLOCK until Welcome window is confirmed
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

# Phase 3: Strict assertion — if Welcome screen is not visible, FAIL
if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
    echo "Current windows:"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
    echo "Attempting one final relaunch..."

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
        echo "FATAL: Welcome screen never appeared. Task cannot proceed."
        exit 1
    fi
fi

# Give extra time for the UI to fully render
sleep 3

# Dismiss any popup dialogs (but not the Welcome dialog itself)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Double-check Welcome is still there
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
    echo "VERIFIED: Autopsy Welcome screen is visible and ready"
else
    echo "ERROR: Welcome screen disappeared after Escape key. Windows:"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
    exit 1
fi

echo "=== Task setup complete ==="
echo "Agent should create case, add $DISK_IMAGE, and examine file metadata."
