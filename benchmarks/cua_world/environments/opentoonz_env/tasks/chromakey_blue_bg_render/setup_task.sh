#!/bin/bash
set -e
echo "=== Setting up chromakey_blue_bg_render task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/chromakey_render"

# 1. Clean up previous run artifacts
echo "Cleaning output directory..."
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify source data
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Attempt to restore from backup or download if missing (resilience)
    # For this task, we assume the environment is set up correctly as per env definition
    exit 1
fi

# 3. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# 4. Start OpenToonz
# We launch it fresh to ensure no stale state
echo "Launching OpenToonz..."
if pgrep -f "opentoonz" > /dev/null; then
    pkill -f "opentoonz"
    sleep 2
fi

su - ga -c "DISPLAY=:1 /snap/bin/opentoonz > /dev/null 2>&1 &" || \
su - ga -c "DISPLAY=:1 opentoonz > /dev/null 2>&1 &"

# 5. Wait for window and maximize
echo "Waiting for OpenToonz window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "Window found."
        break
    fi
    sleep 1
done

sleep 5 # Wait for UI to fully load

# Dismiss potential startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Maximize
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="