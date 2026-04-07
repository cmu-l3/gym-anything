#!/bin/bash
set -e
echo "=== Setting up impact_flash_frame_edit task ==="

# 1. Define paths
SCENE_SRC="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/impact_test"

# 2. Prepare Output Directory (Clean state)
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning output directory..."
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 3. Ensure Sample Scene Exists
if [ ! -f "$SCENE_SRC" ]; then
    echo "Error: Sample scene $SCENE_SRC not found."
    # Try to copy from backup/install location if needed, or fail
    # Assuming environment setup provided it as per specs
    exit 1
fi

# 4. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch/Reset OpenToonz
echo "Ensuring OpenToonz is running..."
if ! pgrep -f "OpenToonz" > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz started."
            break
        fi
        sleep 1
    done
    sleep 5 # Allow UI to settle
fi

# 6. Maximize Window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 7. Dismiss popups (if any remain)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.2
done

# 8. Initial Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="