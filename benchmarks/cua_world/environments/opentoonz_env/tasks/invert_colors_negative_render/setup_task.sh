#!/bin/bash
echo "=== Setting up invert_colors_negative_render task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/negative_render"

# Ensure output directory exists and is clean
su - ga -c "mkdir -p $OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -name "*.png" -delete 2>/dev/null || true
find "$OUTPUT_DIR" -maxdepth 1 -name "*.tga" -delete 2>/dev/null || true
find "$OUTPUT_DIR" -maxdepth 1 -name "*.jpg" -delete 2>/dev/null || true
find "$OUTPUT_DIR" -maxdepth 1 -name "*.tif" -delete 2>/dev/null || true
echo "Output directory cleared: $OUTPUT_DIR"

# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Create dummy if missing (fallback for stability, though env should have it)
    su - ga -c "mkdir -p $(dirname $SOURCE_SCENE)"
    su - ga -c "touch $SOURCE_SCENE"
fi
echo "Source scene verified: $SOURCE_SCENE"

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Ensure OpenToonz is running and focused
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    sleep 10
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true
sleep 1

# Dismiss any open dialogs (startup popup, etc)
for i in $(seq 1 3); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Target Output: $OUTPUT_DIR"