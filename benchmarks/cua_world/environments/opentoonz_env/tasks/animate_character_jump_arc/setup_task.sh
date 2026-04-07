#!/bin/bash
set -e
echo "=== Setting up animate_character_jump_arc task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/jump_arc"

# 1. Clean and prepare output directory
echo "Cleaning output directory..."
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Try to copy from backup if available or fail
    if [ -f "/usr/share/opentoonz/samples/dwanko_run.tnz" ]; then
         cp "/usr/share/opentoonz/samples/dwanko_run.tnz" "$SOURCE_SCENE"
         chown ga:ga "$SOURCE_SCENE"
    else
         echo "Critical: Sample data missing."
         exit 1
    fi
fi

# 3. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(cat /tmp/task_start_timestamp)"

# 4. Launch OpenToonz
echo "Launching OpenToonz..."
# Ensure no previous instances
pkill -f opentoonz 2>/dev/null || true
sleep 1

# Launch as ga user
su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "OpenToonz window detected."
        break
    fi
    sleep 1
done

# Maximize window
sleep 5
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss startup popups if any
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="