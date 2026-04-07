#!/bin/bash
set -e
echo "=== Setting up flip_animation_horizontal_render task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/flipped_walkcycle"

# 1. Clean up and prepare output directory
echo "Cleaning output directory..."
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Attempt to find it in likely locations if moved
    FOUND=$(find /home/ga -name "dwanko_run.tnz" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        echo "Found at $FOUND, symlinking..."
        su - ga -c "mkdir -p $(dirname $SOURCE_SCENE)"
        ln -s "$FOUND" "$SOURCE_SCENE"
    else
        echo "CRITICAL: Could not find dwanko_run.tnz sample file."
        exit 1
    fi
fi
echo "Source scene verified: $SOURCE_SCENE"

# 3. Record initial state
# Count files in output dir (should be 0)
INITIAL_COUNT=$(find "$OUTPUT_DIR" -type f 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_file_count.txt

# Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch OpenToonz (optional but helpful state)
# We don't pre-load the file to force the agent to find and open it,
# but we ensure the app is ready.
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 5. Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="