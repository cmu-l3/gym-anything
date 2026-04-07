#!/bin/bash
echo "=== Setting up pipeline_test_card_render task ==="

# Define paths
OUTPUT_DIR="/home/ga/OpenToonz/output/test_card"

# 1. Clean and prepare output directory
# The task description says "Output directory exists and is empty"
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning existing output directory..."
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Record task start time for anti-gaming (mtime check)
date +%s > /tmp/task_start_time.txt

# 3. Ensure OpenToonz is running
# If not running, start it. If running, try to focus it.
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz > /tmp/opentoonz.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "opentoonz" > /dev/null; then
            echo "OpenToonz started."
            break
        fi
        sleep 1
    done
fi

# 4. Maximize and focus window
sleep 2
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 5. Handle startup dialogs if they appear (just in case)
# Press Escape a few times to dismiss "Startup Popup" or "Project Settings" if they block interaction
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 6. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Output directory prepared: $OUTPUT_DIR"