#!/bin/bash
set -e
echo "=== Setting up extract_keyframe_transparent task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/keyframe_still"

# 1. Clean and Prepare Output Directory
echo "Preparing output directory: $OUTPUT_DIR"
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify Data Availability
if [ ! -f "$SCENE_PATH" ]; then
    echo "ERROR: Source scene $SCENE_PATH not found."
    # Try to find it elsewhere or fail
    FOUND=$(find /home/ga -name "dwanko_run.tnz" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        echo "Found at $FOUND, symlinking..."
        ln -sf "$FOUND" "$SCENE_PATH"
    else
        echo "Critical Error: Sample data missing."
        exit 1
    fi
fi

# 3. Record Task Start Time (Anti-Gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Ensure OpenToonz is Running
# Check if running, if not start it
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz" > /dev/null; then
            echo "OpenToonz window detected."
            break
        fi
        sleep 1
    done
    sleep 5
else
    echo "OpenToonz is already running."
fi

# 5. Set Window State
echo "Maximizing OpenToonz window..."
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Capture Initial State Screenshot
sleep 2
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="