#!/bin/bash
echo "=== Setting up reflection_pool_composite task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/reflection"

# Ensure clean output state
echo "Cleaning output directory..."
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Attempt to recover by checking if sample zip needs expansion or alternative location
    if [ -f "/opt/opentoonz/stuff/samples/dwanko_run.tnz" ]; then
        cp "/opt/opentoonz/stuff/samples/dwanko_run.tnz" "$SOURCE_SCENE"
        echo "Recovered source scene from system install."
    else
        echo "CRITICAL: Cannot find source scene."
        exit 1
    fi
fi

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure OpenToonz is running and focused
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 opentoonz &"
    sleep 10
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Close any lingering dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="