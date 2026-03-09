#!/bin/bash
echo "=== Exporting implement_blob_storage result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if image was downloaded
IMAGE_DOWNLOADED="false"
if [ -f "/home/ga/Downloads/guitar.jpg" ]; then
    IMAGE_SIZE=$(stat -c%s "/home/ga/Downloads/guitar.jpg")
    if [ "$IMAGE_SIZE" -gt 1000 ]; then
        IMAGE_DOWNLOADED="true"
    fi
fi

# Check if ODB was modified
ODB_PATH="/home/ga/chinook.odb"
ODB_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    
    # Copy ODB to temp location for verifier to pull
    # We copy it to /tmp so the verifier can use copy_from_env on a stable path
    cp "$ODB_PATH" /tmp/chinook_submitted.odb
    chmod 644 /tmp/chinook_submitted.odb
fi

# Check if app was running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_modified": $ODB_MODIFIED,
    "odb_size": $ODB_SIZE,
    "image_downloaded": $IMAGE_DOWNLOADED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "submitted_odb_path": "/tmp/chinook_submitted.odb"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Close LibreOffice gracefully to ensure buffers are flushed (if it was running)
kill_libreoffice

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="