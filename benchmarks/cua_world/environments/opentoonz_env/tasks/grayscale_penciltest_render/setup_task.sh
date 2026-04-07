#!/bin/bash
set -e
echo "=== Setting up grayscale_penciltest_render task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/grayscale_test"

# 1. Clean up previous run artifacts
echo "Cleaning output directory..."
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify source data exists
if [ ! -f "$SCENE_PATH" ]; then
    echo "ERROR: Source scene not found at $SCENE_PATH"
    # Attempt to locate it elsewhere if moved
    FOUND_PATH=$(find /home/ga -name "dwanko_run.tnz" 2>/dev/null | head -1)
    if [ -n "$FOUND_PATH" ]; then
        echo "Found at $FOUND_PATH, symlinking..."
        ln -sf "$FOUND_PATH" "$SCENE_PATH"
    else
        echo "Critical: Sample data missing."
        exit 1
    fi
fi

# 3. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch OpenToonz
# We kill any existing instances to ensure a fresh start
pkill -f opentoonz 2>/dev/null || true
sleep 2

echo "Launching OpenToonz..."
# Launching with the scene file argument often opens it directly
su - ga -c "DISPLAY=:1 /snap/bin/opentoonz '$SCENE_PATH' &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 opentoonz '$SCENE_PATH' &"

# 5. Wait for window and maximize
echo "Waiting for OpenToonz window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "opentoonz" > /dev/null; then
        echo "OpenToonz window detected."
        break
    fi
    sleep 1
done

# Small delay to ensure it's fully rendered
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss common startup popups if they appear (Esc key)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="