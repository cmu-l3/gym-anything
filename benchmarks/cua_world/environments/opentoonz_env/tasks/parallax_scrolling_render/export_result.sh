#!/bin/bash
echo "=== Exporting Parallax Task Results ==="

# Paths
OUTPUT_DIR="/home/ga/OpenToonz/output/parallax"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Find rendered PNG files
# Sort by name to ensure sequence order (frame 1, frame 2...)
mapfile -t FRAMES < <(find "$OUTPUT_DIR" -name "*.png" | sort)
FRAME_COUNT=${#FRAMES[@]}

FIRST_FRAME=""
LAST_FRAME=""
FILES_NEWER="false"
TOTAL_SIZE=0

if [ "$FRAME_COUNT" -gt 0 ]; then
    FIRST_FRAME="${FRAMES[0]}"
    LAST_FRAME="${FRAMES[-1]}"
    
    # Check timestamps
    NEWER_COUNT=0
    for f in "${FRAMES[@]}"; do
        F_TIME=$(stat -c %Y "$f")
        if [ "$F_TIME" -gt "$TASK_START" ]; then
            ((NEWER_COUNT++))
        fi
        SIZE=$(stat -c %s "$f")
        TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
    done
    
    if [ "$NEWER_COUNT" -eq "$FRAME_COUNT" ]; then
        FILES_NEWER="true"
    fi
fi

# Prepare JSON result
# We save paths to the first and last frame so the verifier can copy and analyze them
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "frame_count": $FRAME_COUNT,
    "first_frame_path": "$FIRST_FRAME",
    "last_frame_path": "$LAST_FRAME",
    "files_created_during_task": $FILES_NEWER,
    "total_size_bytes": $TOTAL_SIZE
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Frames found: $FRAME_COUNT"
cat /tmp/task_result.json