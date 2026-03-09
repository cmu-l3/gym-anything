#!/bin/bash
echo "=== Setting up web_delivery_trim task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/web_trim"

# Ensure output directory exists and is clean
su - ga -c "mkdir -p $OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 3 \( -name "*.png" -o -name "*.tga" \) -delete 2>/dev/null || true
echo "Output directory cleared: $OUTPUT_DIR"

# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    exit 1
fi
echo "Source scene verified: $SOURCE_SCENE"

# Count initial output files
INITIAL_COUNT=$(find "$OUTPUT_DIR" -maxdepth 3 \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | wc -l)
INITIAL_COUNT=${INITIAL_COUNT:-0}
echo "$INITIAL_COUNT" > /tmp/web_trim_initial_count
echo "Initial output file count: $INITIAL_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Bring OpenToonz to focus
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any open dialogs
for i in $(seq 1 3); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Source scene: $SOURCE_SCENE"
echo "Output dir: $OUTPUT_DIR (empty)"
echo "Timestamp: $(cat /tmp/task_start_timestamp)"
echo "Target: frames 1-16 at 1280x720"
