#!/bin/bash
echo "=== Exporting Blueprint Task Result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/blueprint"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
echo "Analyzing output directory: $OUTPUT_DIR"

# Count PNG files
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
echo "Found $FILE_COUNT PNG files."

# Identify a representative frame (e.g., frame 0006 or the first one found)
SAMPLE_FRAME=""
if [ "$FILE_COUNT" -gt 0 ]; then
    # Sort and pick the middle-ish frame or first one
    SAMPLE_FRAME=$(find "$OUTPUT_DIR" -name "*.png" | sort | head -n 6 | tail -n 1)
fi

# Check timestamps (Anti-Gaming)
FILES_CREATED_DURING_TASK=0
if [ "$FILE_COUNT" -gt 0 ]; then
    FILES_CREATED_DURING_TASK=$(find "$OUTPUT_DIR" -name "*.png" -newermt "@$TASK_START" | wc -l)
fi

# 3. Create JSON Result
# We will save the path to the sample frame so the host verifier can copy it out
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_count": $FILE_COUNT,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "sample_frame_path": "$SAMPLE_FRAME",
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false")
}
EOF

# Move to standard location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json