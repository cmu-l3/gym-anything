#!/bin/bash
echo "=== Setting up walkcycle_hd_render task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/walkcycle_hd"

# Ensure output directory exists and is empty
su - ga -c "mkdir -p $OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -name "*.png" -delete 2>/dev/null || true
find "$OUTPUT_DIR" -maxdepth 1 -name "*.tga" -delete 2>/dev/null || true
find "$OUTPUT_DIR" -maxdepth 1 -name "*.jpg" -delete 2>/dev/null || true
find "$OUTPUT_DIR" -maxdepth 1 -name "*.tif" -delete 2>/dev/null || true
echo "Output directory cleared: $OUTPUT_DIR"

# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    exit 1
fi
echo "Source scene verified: $SOURCE_SCENE"

# Count initial output files (should be 0 after cleanup)
INITIAL_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | wc -l)
INITIAL_COUNT=${INITIAL_COUNT:-0}
echo "$INITIAL_COUNT" > /tmp/walkcycle_hd_initial_count
echo "Initial output file count: $INITIAL_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Bring OpenToonz window to focus and maximize
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
