#!/bin/bash
echo "=== Exporting recolor_character_night_scene results ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/night_scene"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"
ANALYSIS_IMAGE="/tmp/analysis_frame.png"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Find rendered files
# Look for PNG files in the output directory
RENDERED_FILES=$(find "$OUTPUT_DIR" -name "*.png" -type f 2>/dev/null)
FILE_COUNT=$(echo "$RENDERED_FILES" | wc -w)

# 3. Check timestamps (Anti-gaming)
FILES_CREATED_DURING_TASK=0
if [ "$FILE_COUNT" -gt 0 ]; then
    for f in $RENDERED_FILES; do
        MTIME=$(stat -c %Y "$f")
        if [ "$MTIME" -ge "$TASK_START" ]; then
            FILES_CREATED_DURING_TASK=$((FILES_CREATED_DURING_TASK + 1))
        fi
    done
fi

# 4. Prepare a frame for analysis (Verifier needs to inspect pixels)
# Pick the first valid image file
FIRST_FILE=$(echo "$RENDERED_FILES" | head -n 1)
IMAGE_EXISTS=false

if [ -n "$FIRST_FILE" ] && [ -f "$FIRST_FILE" ]; then
    cp "$FIRST_FILE" "$ANALYSIS_IMAGE"
    chmod 644 "$ANALYSIS_IMAGE"
    IMAGE_EXISTS=true
fi

# 5. Create JSON result
# Note: Python verifier will do the heavy lifting of pixel analysis.
# We just pass metadata about the files.
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_count": $FILE_COUNT,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "image_available_for_analysis": $IMAGE_EXISTS,
    "analysis_image_path": "$ANALYSIS_IMAGE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions so verifier (running as host/root) can read
chmod 644 "$RESULT_JSON"

echo "Export complete. Result:"
cat "$RESULT_JSON"