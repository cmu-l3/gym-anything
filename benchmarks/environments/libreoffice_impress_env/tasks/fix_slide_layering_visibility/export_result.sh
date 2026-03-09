#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Slide Layering Result ==="

# Record end time
date +%s > /tmp/task_end_time.txt

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application is running
APP_RUNNING="false"
if pgrep -f "soffice" > /dev/null; then
    APP_RUNNING="true"
    # Try to gracefully close if running, to ensure flush to disk (optional, but safer to just read disk)
    # But instructions said "Save the presentation", so we assume agent saved.
    # We won't force close here to avoid corrupting if agent is midway.
fi

# Define path
FILE_PATH="/home/ga/Documents/Presentations/territory_analysis.odp"
FILE_EXISTS="false"
FILE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Create a copy for the verifier to read safely
    cp "$FILE_PATH" /tmp/task_result.odp
    chmod 666 /tmp/task_result.odp
else
    echo "Result file not found at $FILE_PATH"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "app_running": $APP_RUNNING,
    "task_start_time": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export completed. JSON result:"
cat /tmp/task_result.json