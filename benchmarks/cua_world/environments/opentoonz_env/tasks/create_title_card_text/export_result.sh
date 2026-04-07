#!/bin/bash
echo "=== Exporting create_title_card_text results ==="

# Define paths
OUTPUT_DIR="/home/ga/OpenToonz/output/title_card"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot (Evidence of UI state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
echo "Analyzing output files in $OUTPUT_DIR..."

# Count PNG files
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)

# Check timestamps (Anti-gaming)
# Count how many files were modified AFTER the task started
FRESH_FILES_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -newermt "@$TASK_START_TIME" | wc -l)

# Check file size (Basic content check - empty files are usually < 1KB)
# Get average file size in bytes
TOTAL_SIZE=$(du -sb "$OUTPUT_DIR" 2>/dev/null | cut -f1)
AVG_SIZE=0
if [ "$FILE_COUNT" -gt 0 ]; then
    AVG_SIZE=$((TOTAL_SIZE / FILE_COUNT))
fi

# 3. Attempt text detection (Optional/Fallback)
# We might not have OCR installed in the env, so we rely on VLM in verifier.py
# But we can check if the files are just solid colors or have content variability
CONTENT_VARIABILITY="unknown"
if command -v identify >/dev/null; then
    # Check standard deviation of the first image to ensure it's not blank
    FIRST_IMG=$(find "$OUTPUT_DIR" -name "*.png" | head -n 1)
    if [ -f "$FIRST_IMG" ]; then
        STD_DEV=$(identify -format "%[standard_deviation]" "$FIRST_IMG" 2>/dev/null || echo "0")
        echo "Image standard deviation: $STD_DEV"
        CONTENT_VARIABILITY="$STD_DEV"
    fi
fi

# 4. Generate Result JSON
JSON_PATH="/tmp/task_result.json"
cat > "$JSON_PATH" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false"),
    "file_count": $FILE_COUNT,
    "fresh_files_count": $FRESH_FILES_COUNT,
    "avg_file_size_bytes": $AVG_SIZE,
    "content_variability": "$CONTENT_VARIABILITY",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions for copy_from_env
chmod 644 "$JSON_PATH"
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "Result JSON generated:"
cat "$JSON_PATH"
echo "=== Export complete ==="