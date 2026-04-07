#!/bin/bash
set -e
echo "=== Setting up ghost_opacity_alpha_render task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/ghost_render"

# 1. Clean and prepare output directory
echo "Cleaning output directory..."
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Attempt to copy from known location if missing, or fail
    if [ -f "/usr/share/opentoonz/samples/dwanko_run.tnz" ]; then
        cp "/usr/share/opentoonz/samples/dwanko_run.tnz" "$SOURCE_SCENE"
    else
        echo "Source file missing. Task cannot proceed."
        exit 1
    fi
fi

# 3. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Start OpenToonz
# Close any existing instances
pkill -f opentoonz 2>/dev/null || true
sleep 2

echo "Starting OpenToonz..."
# Launch empty or with scene - usually better to launch empty so agent has to load
su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"

# Wait for window
echo "Waiting for OpenToonz window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5

# 5. Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="