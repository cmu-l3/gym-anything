#!/bin/bash
echo "=== Exporting underwater_wave_distortion_fx results ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/underwater_fx"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
echo "Analyzing output files in $OUTPUT_DIR..."

# Count PNG files
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)

# Check timestamps (Anti-Gaming)
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_time.txt | wc -l)

# Get First Frame for VLM Verification
FIRST_FRAME=$(find "$OUTPUT_DIR" -name "*.png" | sort | head -1)
FRAME_PATH=""

if [ -f "$FIRST_FRAME" ]; then
    echo "Found first frame: $FIRST_FRAME"
    # Copy to temp for export
    cp "$FIRST_FRAME" /tmp/agent_render_frame.png
    FRAME_PATH="/tmp/agent_render_frame.png"
    
    # Get File Size
    TOTAL_SIZE_BYTES=$(du -sb "$OUTPUT_DIR" | cut -f1)
else
    echo "No output frames found."
    TOTAL_SIZE_BYTES=0
fi

# 3. Check if OpenToonz is still running
APP_RUNNING=$(pgrep -f "OpenToonz" > /dev/null && echo "true" || echo "false")

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_count": $FILE_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "total_size_bytes": $TOTAL_SIZE_BYTES,
    "app_was_running": $APP_RUNNING,
    "frame_sample_path": "$FRAME_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json