#!/bin/bash
echo "=== Setting up underwater_wave_distortion_fx task ==="

SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/underwater_fx"

# 1. Ensure clean state
echo "Cleaning output directory..."
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/* 2>/dev/null || true

# 2. Verify source data
if [ ! -f "$SCENE_PATH" ]; then
    echo "ERROR: Source scene $SCENE_PATH not found."
    # Try to find it if it moved
    FOUND=$(find /home/ga -name "dwanko_run.tnz" | head -1)
    if [ -n "$FOUND" ]; then
        echo "Found at $FOUND, using that."
        SCENE_PATH="$FOUND"
    else
        echo "CRITICAL: Sample data missing."
        exit 1
    fi
fi

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch OpenToonz (Desktop App Setup Pattern)
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize and Focus
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="