#!/bin/bash
echo "=== Setting up Visual Echo task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/echo_effect"

# 1. Clean previous outputs
echo "Cleaning output directory..."
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.png 2>/dev/null || true
rm -f "$OUTPUT_DIR"/*.tga 2>/dev/null || true

# 2. Verify input data
if [ ! -f "$SCENE_PATH" ]; then
    echo "ERROR: Sample scene not found at $SCENE_PATH"
    # Try to copy from system samples if missing
    SYSTEM_SAMPLE=$(find /opt /usr -name "dwanko_run.tnz" 2>/dev/null | head -1)
    if [ -n "$SYSTEM_SAMPLE" ]; then
        cp "$SYSTEM_SAMPLE" "$SCENE_PATH"
        chown ga:ga "$SCENE_PATH"
        echo "Restored sample scene from system."
    else
        echo "CRITICAL: Could not find dwanko_run.tnz"
    fi
fi

# 3. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Launch OpenToonz
# We launch it fresh so the agent starts from a known state
echo "Launching OpenToonz..."
pkill -f opentoonz 2>/dev/null || true
sleep 1

# Launch as user 'ga'
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
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 5. Capture Initial State Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="