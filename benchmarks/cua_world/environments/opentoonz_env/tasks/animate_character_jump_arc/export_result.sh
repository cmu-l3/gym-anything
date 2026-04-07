#!/bin/bash
echo "=== Exporting animate_character_jump_arc result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/jump_arc"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
# Find all PNG files in the output directory
# Sort them to identify the sequence
FILES=($(find "$OUTPUT_DIR" -name "*.png" | sort))
FILE_COUNT=${#FILES[@]}

echo "Found $FILE_COUNT PNG files."

# Check if files were created during task
CREATED_DURING_TASK="false"
if [ "$FILE_COUNT" -gt 0 ]; then
    LAST_FILE="${FILES[-1]}"
    FILE_TIME=$(stat -c %Y "$LAST_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Identify specific frames for trajectory verification
# We need roughly frame 1 (start), frame 12 (mid), and frame 24 (end)
# We map indices 0, 11, 23 from the sorted array
FRAME_START=""
FRAME_MID=""
FRAME_END=""

if [ "$FILE_COUNT" -ge 24 ]; then
    FRAME_START="${FILES[0]}"
    FRAME_MID="${FILES[11]}"
    FRAME_END="${FILES[23]}"
elif [ "$FILE_COUNT" -ge 3 ]; then
    # Fallback for partial renders: Start, Middle, End
    FRAME_START="${FILES[0]}"
    MID_IDX=$((FILE_COUNT / 2))
    FRAME_MID="${FILES[$MID_IDX]}"
    FRAME_END="${FILES[-1]}"
fi

# 4. Prepare files for verifier (copy to /tmp/ for easy access by copy_from_env)
if [ -n "$FRAME_START" ]; then
    cp "$FRAME_START" /tmp/verify_frame_start.png
    cp "$FRAME_MID" /tmp/verify_frame_mid.png
    cp "$FRAME_END" /tmp/verify_frame_end.png
    chmod 644 /tmp/verify_frame_*.png
fi

# 5. Create JSON result
JSON_PATH="/tmp/task_result.json"
cat > "$JSON_PATH" << EOF
{
    "file_count": $FILE_COUNT,
    "created_during_task": $CREATED_DURING_TASK,
    "frame_start_path": "/tmp/verify_frame_start.png",
    "frame_mid_path": "/tmp/verify_frame_mid.png",
    "frame_end_path": "/tmp/verify_frame_end.png",
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF
chmod 666 "$JSON_PATH"

echo "Export complete. Result:"
cat "$JSON_PATH"