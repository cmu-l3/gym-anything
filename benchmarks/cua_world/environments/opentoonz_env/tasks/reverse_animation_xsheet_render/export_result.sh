#!/bin/bash
echo "=== Exporting reverse_animation_xsheet_render results ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/reversed_animation"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check output files
if [ -d "$OUTPUT_DIR" ]; then
    # Count PNG files
    FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
    
    # Calculate total size
    TOTAL_SIZE_BYTES=$(du -sb "$OUTPUT_DIR" 2>/dev/null | cut -f1 || echo "0")
    
    # Check timestamps (anti-gaming)
    # Count how many files were modified AFTER task start
    NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -newermt "@$TASK_START" | wc -l)
else
    FILE_COUNT=0
    TOTAL_SIZE_BYTES=0
    NEW_FILES_COUNT=0
fi

# 3. Compile frame sequence for verification
# We need to list the files in alphanumeric order to reconstructing the sequence
FRAMES_LIST=$(find "$OUTPUT_DIR" -name "*.png" | sort | tr '\n' ',' | sed 's/,$//')

# 4. Create JSON result
JSON_FILE="/tmp/task_result.json"
cat > "$JSON_FILE" << EOF
{
    "file_count": $FILE_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "total_size_bytes": $TOTAL_SIZE_BYTES,
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false"),
    "frames_list": "$FRAMES_LIST",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 "$JSON_FILE" 2>/dev/null || true

echo "Export complete. Result:"
cat "$JSON_FILE"