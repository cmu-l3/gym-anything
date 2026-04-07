#!/bin/bash
set -e
echo "=== Setting up apply_rgb_shift_aberration_fx task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/aberration"

# 1. Clean and Prepare Output Directory
echo "Cleaning output directory: $OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/* 2>/dev/null || true

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Ensure OpenToonz is Running
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" 2>/dev/null || su - ga -c "DISPLAY=:1 opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
            echo "OpenToonz window detected."
            break
        fi
        sleep 1
    done
    sleep 10 # Allow full initialization
fi

# 4. Set Window State (Maximize and Focus)
echo "Maximizing OpenToonz window..."
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 5. Dismiss Startup Dialogs (if any remain)
echo "Dismissing dialogs..."
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 6. Verify Source Scene Exists
if [ ! -f "$SCENE_PATH" ]; then
    echo "ERROR: Source scene $SCENE_PATH not found!"
    # Try to find it elsewhere or copy from backup
    FOUND=$(find /home/ga -name "dwanko_run.tnz" | head -n 1)
    if [ -n "$FOUND" ]; then
        echo "Found at $FOUND, copying..."
        su - ga -c "mkdir -p /home/ga/OpenToonz/samples/"
        cp "$FOUND" "$SCENE_PATH"
        chown ga:ga "$SCENE_PATH"
    fi
fi

# 7. Capture Initial State Screenshot
echo "Capturing initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="