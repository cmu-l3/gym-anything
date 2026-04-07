#!/bin/bash
echo "=== Setting up pip_corner_composition_render task ==="

# Task variables
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/pip_corner"

# 1. Clean and prepare output directory
echo "Cleaning output directory: $OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"
# Remove any existing images to prevent false positives
find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" \) -delete 2>/dev/null || true

# 2. Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Try to copy from backup location if standard path fails (robustness)
    if [ -f "/usr/share/opentoonz/samples/dwanko_run.tnz" ]; then
        cp "/usr/share/opentoonz/samples/dwanko_run.tnz" "$SOURCE_SCENE"
        chown ga:ga "$SOURCE_SCENE"
    else
        echo "Creating dummy scene file if missing (fallback)"
        touch "$SOURCE_SCENE"
    fi
fi

# 3. Record initial state
# Count files (should be 0)
INITIAL_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 -type f | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_file_count.txt

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Ensure OpenToonz is running and focused
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 5. Dismiss startup dialogs (popups)
sleep 2
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="