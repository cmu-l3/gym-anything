#!/bin/bash
echo "=== Setting up square_scene_colorcard_render task ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/square_scene"

# 1. Clean up previous artifacts
echo "Cleaning output directory: $OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.png 2>/dev/null || true
rm -f "$OUTPUT_DIR"/*.tga 2>/dev/null || true
rm -f "$OUTPUT_DIR"/*.tif 2>/dev/null || true

# 2. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Ensure OpenToonz is running
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" || su - ga -c "DISPLAY=:1 opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
            echo "OpenToonz started."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 4. Maximize and focus the window
echo "Focusing OpenToonz..."
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 5. Dismiss any potential dialogs (like "Save Scene?")
# Press Escape a few times to clear blocking dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 6. Capture initial state screenshot
echo "Capturing initial screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="