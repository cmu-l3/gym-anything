#!/bin/bash
set -e
echo "=== Setting up spritesheet_game_export task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_BASE="/home/ga/OpenToonz/output"
FRAMES_DIR="$OUTPUT_BASE/spritesheet_frames"
SPRITESHEET_PATH="$OUTPUT_BASE/spritesheet.png"

# Ensure directories exist and are owned by ga
su - ga -c "mkdir -p $OUTPUT_BASE"
su - ga -c "mkdir -p $FRAMES_DIR"

# Clean up previous runs
echo "Cleaning up output directories..."
rm -f "$FRAMES_DIR"/*.png 2>/dev/null || true
rm -f "$FRAMES_DIR"/*.tga 2>/dev/null || true
rm -f "$SPRITESHEET_PATH" 2>/dev/null || true

# Verify sample data exists
if [ ! -f "$SCENE_PATH" ]; then
    echo "ERROR: Sample scene not found at $SCENE_PATH"
    # Try to find it elsewhere or fail
    FOUND=$(find /home/ga -name "dwanko_run.tnz" | head -n 1)
    if [ -n "$FOUND" ]; then
        echo "Found at $FOUND, symlinking..."
        ln -sf "$FOUND" "$SCENE_PATH"
    else
        echo "CRITICAL: Scene file missing."
        exit 1
    fi
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure OpenToonz is running
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz" > /dev/null; then
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

# Dismiss any startup dialogs (common in OT)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="