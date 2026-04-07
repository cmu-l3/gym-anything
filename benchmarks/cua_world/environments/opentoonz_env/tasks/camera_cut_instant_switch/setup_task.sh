#!/bin/bash
set -e
echo "=== Setting up camera_cut_instant_switch task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/camera_cut"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ensure source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "Error: Source scene $SOURCE_SCENE not found."
    exit 1
fi

# Clean output directory
echo "Cleaning output directory..."
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.png 2>/dev/null || true
rm -f "$OUTPUT_DIR"/*.tga 2>/dev/null || true

# Ensure OpenToonz is running or start it
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz" > /dev/null; then
            echo "OpenToonz window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any potential dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="