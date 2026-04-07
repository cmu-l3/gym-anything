#!/bin/bash
set -e
echo "=== Setting up create_character_color_palette task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty
OUTPUT_DIR="/home/ga/OpenToonz/outputs"
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR/cyber_detective.tpl" 2>/dev/null || true

# Ensure OpenToonz is running
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    # Launch OpenToonz (using the custom launcher from env setup)
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz > /tmp/opentoonz.log 2>&1 &"
    
    # Wait for window to appear
    echo "Waiting for OpenToonz window..."
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz detected."
            break
        fi
        sleep 1
    done
    
    # Allow extra time for initialization
    sleep 5
fi

# Maximize the window (Critical for finding the Palette Editor)
echo "Maximizing OpenToonz..."
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any potential startup popups (common in OpenToonz)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="