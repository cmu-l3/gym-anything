#!/bin/bash
set -e
echo "=== Setting up retro_vga_framerange_render task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/retro_vga"

# 1. Prepare Output Directory
# Ensure output directory exists and is empty
su - ga -c "mkdir -p $OUTPUT_DIR"
# Clean up any previous runs to ensure fresh start
find "$OUTPUT_DIR" -maxdepth 1 -type f -delete 2>/dev/null || true
echo "Output directory cleared: $OUTPUT_DIR"

# 2. Verify Data Source
# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Attempt to find it if moved
    FOUND_SCENE=$(find /home/ga/OpenToonz -name "dwanko_run.tnz" | head -n 1)
    if [ -n "$FOUND_SCENE" ]; then
        echo "Found at $FOUND_SCENE, symlinking..."
        ln -s "$FOUND_SCENE" "$SOURCE_SCENE"
    else
        echo "Critical Error: Sample data missing."
        exit 1
    fi
fi
echo "Source scene verified: $SOURCE_SCENE"

# 3. State Recording
# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 4. App Setup
# Check if OpenToonz is running, if not start it? 
# Usually better to let agent start it or have it running. 
# We'll ensure it's running for convenience in this task type.
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
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

# Dismiss common startup popups
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 5. Evidence
# Take initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="