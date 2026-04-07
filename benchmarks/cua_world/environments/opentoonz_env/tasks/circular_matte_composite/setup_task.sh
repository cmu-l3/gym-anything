#!/bin/bash
set -e
echo "=== Setting up circular_matte_composite task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/matte_test"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# 1. Clean up previous output
echo "Cleaning output directory..."
su - ga -c "mkdir -p $OUTPUT_DIR"
# Remove any existing images to ensure we verify fresh renders
find "$OUTPUT_DIR" -type f -delete 2>/dev/null || true

# 2. Ensure OpenToonz is running and focused
# We kill it first to ensure a clean state, or we could just focus it.
# For consistency, let's ensure it's running.
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "Window found."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 3. Dismiss any pesky startup dialogs (common in OT)
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.2
done

# 4. Verify source data exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene $SOURCE_SCENE not found!"
    # Try to copy from backup if available, or just fail
    exit 1
fi

# 5. Take initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="