#!/bin/bash
echo "=== Exporting Reorder Slides Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/Presentations/emergency_preparedness.pptx"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if file exists
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE")
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE")
    
    # Check if modified during task
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        WAS_MODIFIED="true"
    else
        WAS_MODIFIED="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE=0
    FILE_MTIME=0
    WAS_MODIFIED="false"
    
    # Check if user saved as ODP instead
    if [ -f "${TARGET_FILE%.*}.odp" ]; then
        TARGET_FILE="${TARGET_FILE%.*}.odp"
        FILE_EXISTS="true"
        WAS_MODIFIED="true" # New file created
        echo "Found ODP file instead: $TARGET_FILE"
    fi
fi

# Check if Impress is still running
if pgrep -f "soffice.bin" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# Create result JSON
cat > "$RESULT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$TARGET_FILE",
    "was_modified": $WAS_MODIFIED,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "task_start": $TASK_START_TIME,
    "file_mtime": $FILE_MTIME
}
EOF

# Copy the presentation file to /tmp for the verifier to access easily
# (Verifier will use copy_from_env on this path)
if [ "$FILE_EXISTS" = "true" ]; then
    cp "$TARGET_FILE" /tmp/verification_target.pptx 2>/dev/null || cp "$TARGET_FILE" /tmp/verification_target.odp 2>/dev/null || true
    chmod 666 /tmp/verification_target.* 2>/dev/null || true
fi

# Fix permissions on JSON
chmod 666 "$RESULT_JSON"

echo "Export complete. Result:"
cat "$RESULT_JSON"