#!/bin/bash
echo "=== Setting up animation_mp4_export task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/video_export"

# Ensure output directory exists and is clean
su - ga -c "mkdir -p $OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 2 \( -name "*.mp4" -o -name "*.mov" -o -name "*.avi" \
    -o -name "*.webm" -o -name "*.mkv" -o -name "*.flv" \) -delete 2>/dev/null || true
echo "Output directory cleared: $OUTPUT_DIR"

# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    exit 1
fi
echo "Source scene verified: $SOURCE_SCENE"

# Record initial state (should be empty)
INITIAL_COUNT=$(find "$OUTPUT_DIR" -maxdepth 2 \( -name "*.mp4" -o -name "*.mov" \
    -o -name "*.avi" -o -name "*.webm" -o -name "*.mkv" \) -type f 2>/dev/null | wc -l)
INITIAL_COUNT=${INITIAL_COUNT:-0}
echo "$INITIAL_COUNT" > /tmp/mp4_export_initial_count
echo "Initial video file count: $INITIAL_COUNT"

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
