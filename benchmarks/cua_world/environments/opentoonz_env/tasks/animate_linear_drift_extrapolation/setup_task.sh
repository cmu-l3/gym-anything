#!/bin/bash
set -e
echo "=== Setting up animate_linear_drift_extrapolation task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/drift"

# record start time
date +%s > /tmp/task_start_time.txt

# Create output directory and clean it
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# Ensure sample scene exists
if [ ! -f "$SCENE_PATH" ]; then
    echo "Error: Sample scene not found at $SCENE_PATH"
    # Try to copy from backup/installation source if missing
    if [ -f "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" ]; then
        cp "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" "$SCENE_PATH"
    fi
fi

# Ensure OpenToonz is running
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected."
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any startup popups
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="