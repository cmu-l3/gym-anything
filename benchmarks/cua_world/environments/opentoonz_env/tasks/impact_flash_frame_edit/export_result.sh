#!/bin/bash
echo "=== Exporting impact_flash_frame_edit results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_DIR="/home/ga/OpenToonz/output/impact_test"

# 3. Check for Output Files
# OpenToonz usually names sequence files like name.0012.png or name_0012.png
# We look for the specific target frame (12) and neighbors (11, 13)
# Frame numbering usually starts at 0001 or 0000. Assuming 1-based from task description "Frames 1-24".
# We'll list what we find to help the verifier.

FRAME_12_PATH=""
FRAME_11_PATH=""
FRAME_13_PATH=""

# Find frame 12 (allowing for various naming conventions: .0012.png, _0012.png, 0012.png)
FRAME_12_CANDIDATE=$(find "$OUTPUT_DIR" -name "*0012.png" | head -n 1)
if [ -f "$FRAME_12_CANDIDATE" ]; then
    FRAME_12_PATH="$FRAME_12_CANDIDATE"
fi

FRAME_11_CANDIDATE=$(find "$OUTPUT_DIR" -name "*0011.png" | head -n 1)
if [ -f "$FRAME_11_CANDIDATE" ]; then
    FRAME_11_PATH="$FRAME_11_CANDIDATE"
fi

FRAME_13_CANDIDATE=$(find "$OUTPUT_DIR" -name "*0013.png" | head -n 1)
if [ -f "$FRAME_13_CANDIDATE" ]; then
    FRAME_13_PATH="$FRAME_13_CANDIDATE"
fi

# Count total PNGs
TOTAL_PNG_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)

# Check timestamps of the found files
FILES_CREATED_DURING_TASK="false"
if [ -n "$FRAME_12_PATH" ]; then
    F12_MTIME=$(stat -c %Y "$FRAME_12_PATH")
    if [ "$F12_MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# 4. Generate JSON Report
# We output paths so the verifier can copy the specific images for pixel analysis
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false"),
    "total_png_count": $TOTAL_PNG_COUNT,
    "frame_11_path": "$FRAME_11_PATH",
    "frame_12_path": "$FRAME_12_PATH",
    "frame_13_path": "$FRAME_13_PATH",
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "app_running": $(pgrep -f "OpenToonz" > /dev/null && echo "true" || echo "false")
}
EOF

# 5. Move to shared location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="