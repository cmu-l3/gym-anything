#!/bin/bash
echo "=== Exporting optimize_patrol_route results ==="

TASK_START=$(cat C:/tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_PATH="C:/workspace/optimized_patrol.gpx"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

# Check if the expected output GPX file was created
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    
    # Get file size
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || stat -f %z "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if modified/created after task start
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || stat -f %m "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if BaseCamp is running
APP_RUNNING=$(powershell.exe -Command "if (Get-Process BaseCamp -ErrorAction SilentlyContinue) { Write-Output 'true' } else { Write-Output 'false' }" | tr -d '\r')
if [ -z "$APP_RUNNING" ]; then APP_RUNNING="false"; fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Write result metadata
cat > C:/tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING
}
EOF

echo "Result metadata saved to C:/tmp/task_result.json"
cat C:/tmp/task_result.json
echo "=== Export complete ==="