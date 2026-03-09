#!/bin/bash
echo "=== Exporting DDD Event Storming Results ==="

# 1. Define paths
DIAGRAM_PATH="/home/ga/Diagrams/library_event_storming.drawio"
EXPORT_PATH="/home/ga/Diagrams/exports/library_event_storming.png"
TRANSCRIPT_PATH="/home/ga/Desktop/storming_transcript.txt"

# 2. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Check File Existence & Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_MODIFIED="false"
EXPORT_EXISTS="false"

if [ -f "$DIAGRAM_PATH" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$DIAGRAM_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
fi

# 4. Check if draw.io is running
APP_RUNNING=$(pgrep -f "drawio" > /dev/null && echo "true" || echo "false")

# 5. Create JSON Result
# Note: We are NOT parsing the XML here. We will do that in Python for robustness.
# We just export metadata here.
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "export_exists": $EXPORT_EXISTS,
    "app_running": $APP_RUNNING,
    "diagram_path": "$DIAGRAM_PATH",
    "export_path": "$EXPORT_PATH"
}
EOF

# 6. Ensure permissions for copy_from_env
chmod 644 /tmp/task_result.json
chmod 644 "$DIAGRAM_PATH" 2>/dev/null || true
chmod 644 "$EXPORT_PATH" 2>/dev/null || true

echo "=== Export complete ==="