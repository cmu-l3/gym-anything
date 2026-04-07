#!/bin/bash
set -e
echo "=== Setting up apply_mosaic_censor_fx task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/mosaic_censor"

# 1. Clean previous state
echo "Cleaning output directory..."
rm -rf "$OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Ensure sample data exists
if [ ! -f "$SCENE_PATH" ]; then
    echo "ERROR: Sample scene not found at $SCENE_PATH"
    # Try to recover standard sample if missing (fallback logic)
    if [ -f "/home/ga/OpenToonz/samples/dwanko/dwanko_run.tnz" ]; then
        cp "/home/ga/OpenToonz/samples/dwanko/dwanko_run.tnz" "$SCENE_PATH"
    fi
fi

# 3. Setup Anti-Gaming Timestamps
date +%s > /tmp/task_start_time.txt

# 4. Launch OpenToonz (Optional convenience for the agent)
# We launch it so the agent lands in the app immediately
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize Window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Capture Initial State
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="