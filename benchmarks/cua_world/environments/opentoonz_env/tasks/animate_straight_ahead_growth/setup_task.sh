#!/bin/bash
set -e
echo "=== Setting up animate_straight_ahead_growth task ==="

# Define paths
OUTPUT_DIR="/home/ga/OpenToonz/output/growth_anim"

# 1. Clean state: Ensure output directory exists and is empty
echo "Cleaning output directory..."
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Ensure OpenToonz is running and ready
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz > /tmp/opentoonz.log 2>&1 &"
    
    # Wait for window to appear
    echo "Waiting for OpenToonz window..."
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz detected."
            break
        fi
        sleep 1
    done
    
    # Allow extra time for initialization
    sleep 5
fi

# 4. Maximize and focus the window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 5. Dismiss any startup popups (e.g. 'Tip of the Day' or 'Startup')
# Try pressing Escape a few times
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 6. Capture initial state screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Target Output Directory: $OUTPUT_DIR"