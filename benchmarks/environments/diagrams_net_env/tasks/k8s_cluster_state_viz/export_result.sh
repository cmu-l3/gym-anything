#!/bin/bash
set -e

echo "=== Exporting k8s_cluster_state_viz results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File paths
DRAWIO_FILE="/home/ga/Diagrams/cluster_state.drawio"
PNG_FILE="/home/ga/Diagrams/cluster_state.png"

# Check file existence and timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    FILE_SIZE=$(stat -c %s "$DRAWIO_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check PNG export
PNG_EXISTS="false"
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_MTIME=$(stat -c %Y "$PNG_FILE")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    else
        PNG_CREATED_DURING_TASK="false"
    fi
else
    PNG_CREATED_DURING_TASK="false"
fi

# App Status
APP_RUNNING=$(pgrep -f "drawio" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
# Note: We rely on the python verifier to parse the actual XML content.
# This JSON provides metadata and timestamp verification.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drawio_exists": $FILE_EXISTS,
    "drawio_created_during_task": $FILE_CREATED_DURING_TASK,
    "drawio_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_created_during_task": $PNG_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="