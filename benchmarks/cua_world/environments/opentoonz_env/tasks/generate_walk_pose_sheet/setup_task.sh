#!/bin/bash
echo "=== Setting up generate_walk_pose_sheet task ==="

# Define paths
OUTPUT_DIR="/home/ga/OpenToonz/output/pose_sheet"
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"

# Ensure output directory exists and is empty
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR/poses.png" 2>/dev/null || true
rm -f "$OUTPUT_DIR"/* 2>/dev/null || true
echo "Output directory cleared: $OUTPUT_DIR"

# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Attempt to locate it if moved
    FOUND_SCENE=$(find /home/ga/OpenToonz -name "dwanko_run.tnz" | head -1)
    if [ -n "$FOUND_SCENE" ]; then
        SOURCE_SCENE="$FOUND_SCENE"
        echo "Found scene at alternative location: $SOURCE_SCENE"
    else
        echo "CRITICAL: Sample scene missing."
        exit 1
    fi
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Prepare OpenToonz
# We relaunch to ensure a clean state, preferably maximizing the window
pkill -f opentoonz 2>/dev/null || true
sleep 2

echo "Launching OpenToonz..."
# Launch empty or with scene? Task says "Open the scene", implies agent does it.
# But loading it for them is helpful for "hard" tasks to focus on the goal.
# However, description says "Open the sample scene...", so agent should do it.
# We will launch empty OpenToonz.
su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" > /dev/null 2>&1
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
        echo "OpenToonz window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss popup dialogs if any (startup popup)
sleep 5
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="