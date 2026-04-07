#!/bin/bash
echo "=== Setting up social_media_vertical_render task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/vertical_social"

# Ensure output directory exists and is empty (Clean State)
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning existing output directory..."
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"
echo "Output directory prepared: $OUTPUT_DIR"

# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Attempt to locate it if moved
    FOUND_SCENE=$(find /home/ga -name "dwanko_run.tnz" 2>/dev/null | head -1)
    if [ -n "$FOUND_SCENE" ]; then
        echo "Found scene at: $FOUND_SCENE"
        SOURCE_SCENE="$FOUND_SCENE"
    else
        echo "Critical Error: Sample scene dwanko_run.tnz missing from environment."
        # Create a dummy file if strictly necessary for testing logic, but real data preferred
        # exit 1
    fi
else
    echo "Source scene verified: $SOURCE_SCENE"
fi

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp recorded: $(cat /tmp/task_start_timestamp)"

# Ensure OpenToonz is running and maximized
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" || su - ga -c "DISPLAY=:1 opentoonz &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "opentoonz"; then
            echo "OpenToonz window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any potential startup popups
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="