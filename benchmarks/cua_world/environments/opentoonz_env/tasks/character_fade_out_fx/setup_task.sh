#!/bin/bash
set -e
echo "=== Setting up character_fade_out_fx task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/fade_out"

# 1. Clean previous outputs
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning output directory..."
    rm -rf "$OUTPUT_DIR"/*
else
    mkdir -p "$OUTPUT_DIR"
fi
# Ensure permissions
chown -R ga:ga "$OUTPUT_DIR"

# 2. Verify source data
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene $SOURCE_SCENE not found!"
    # Try to copy from backup/installation source if missing, or fail
    if [ -f "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" ]; then
        cp "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" "$SOURCE_SCENE"
    else
        echo "Critical: Sample data missing."
    fi
fi

# 3. Ensure OpenToonz is running and ready
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz > /tmp/opentoonz.log 2>&1 &"
    
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

# 4. Maximize and focus
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 5. Dismiss any startup dialogs/popups that might block interaction
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 6. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="