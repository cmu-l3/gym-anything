#!/bin/bash
echo "=== Setting up export_level_png_sequence task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/level_frames"

# 1. Prepare Output Directory
# Ensure it exists and is completely empty to prevent false positives
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -rf "$OUTPUT_DIR"/*
echo "Output directory cleared: $OUTPUT_DIR"

# 2. Verify Data Availability
# Ensure the sample scene exists. If not, try to recover or fail.
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Attempt to locate it if moved
    FOUND_SCENE=$(find /home/ga/OpenToonz -name "dwanko_run.tnz" 2>/dev/null | head -1)
    if [ -n "$FOUND_SCENE" ]; then
        echo "Found scene at $FOUND_SCENE, copying to expected location..."
        mkdir -p "$(dirname "$SOURCE_SCENE")"
        cp "$FOUND_SCENE" "$SOURCE_SCENE"
        chown ga:ga "$SOURCE_SCENE"
    else
        echo "CRITICAL: Could not find dwanko_run.tnz. Task cannot proceed."
        exit 1
    fi
fi
echo "Source scene verified: $SOURCE_SCENE"

# 3. Anti-Gaming Setup
# Record timestamp to verify files are created *during* the task
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 4. Application Setup
# Start OpenToonz maximized
echo "Starting OpenToonz..."
pkill -f opentoonz 2>/dev/null || true
sleep 1

# Launch as ga user
su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" || su - ga -c "DISPLAY=:1 opentoonz &"

# Wait for window
echo "Waiting for OpenToonz window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "OpenToonz detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss common startup popups
sleep 5
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 5. Evidence
# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="