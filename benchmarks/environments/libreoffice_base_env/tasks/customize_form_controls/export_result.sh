#!/bin/bash
echo "=== Exporting Customize Form Controls Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE closing app (to see if form is open)
take_screenshot /tmp/task_final.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Gracefully close LibreOffice to ensure ODB is saved and flushed
echo "Closing LibreOffice to save changes..."
if is_libreoffice_running; then
    # Try friendly close first
    DISPLAY=:1 wmctrl -c "LibreOffice" 2>/dev/null || true
    DISPLAY=:1 wmctrl -c "chinook.odb" 2>/dev/null || true
    sleep 2
    # Then kill if needed
    kill_libreoffice
fi

# Check ODB file status
ODB_PATH="/home/ga/chinook.odb"
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    ODB_MTIME=$(stat -c %Y "$ODB_PATH")
    
    # Check if modified since start
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="