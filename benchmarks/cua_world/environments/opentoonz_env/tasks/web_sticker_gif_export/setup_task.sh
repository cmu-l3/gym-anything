#!/bin/bash
echo "=== Setting up web_sticker_gif_export task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/sticker"
OUTPUT_FILE="$OUTPUT_DIR/dwanko.gif"

# 1. Clean up previous artifacts
echo "Cleaning output directory..."
if [ -d "$OUTPUT_DIR" ]; then
    rm -f "$OUTPUT_DIR"/*.gif
else
    su - ga -c "mkdir -p $OUTPUT_DIR"
fi

# 2. Verify source data exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Fallback: try to find it elsewhere or fail
    FOUND=$(find /home/ga -name "dwanko_run.tnz" | head -n 1)
    if [ -n "$FOUND" ]; then
        echo "Found scene at $FOUND, symlinking..."
        ln -sf "$FOUND" "$SOURCE_SCENE"
    else
        echo "CRITICAL: Could not find dwanko_run.tnz"
        exit 1
    fi
fi

# 3. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Ensure OpenToonz is running
# We kill existing instances to ensure a clean state, then launch
pkill -f opentoonz 2>/dev/null || true
sleep 2

echo "Starting OpenToonz..."
# Launching with the scene file argument if possible, otherwise just launch
su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"

# Wait for window
echo "Waiting for OpenToonz window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "OpenToonz detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 5. Dismiss startup dialogs
sleep 5
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 6. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="