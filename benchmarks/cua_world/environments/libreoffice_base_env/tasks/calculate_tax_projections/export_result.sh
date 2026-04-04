#!/bin/bash
echo "=== Exporting calculate_tax_projections result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")

ODB_PATH="/home/ga/chinook.odb"

# Check ODB status
if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$ODB_MTIME" -gt "$INITIAL_MTIME" ] && [ "$ODB_MTIME" -ge "$TASK_START" ]; then
        ODB_MODIFIED="true"
    else
        ODB_MODIFIED="false"
    fi
else
    ODB_EXISTS="false"
    ODB_SIZE="0"
    ODB_MTIME="0"
    ODB_MODIFIED="false"
fi

# Check if LibreOffice is running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "odb_path": "$ODB_PATH",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Prepare ODB for verification (copy to temp to avoid locking issues)
if [ "$ODB_EXISTS" = "true" ]; then
    cp "$ODB_PATH" /tmp/chinook_verify.odb
    chmod 666 /tmp/chinook_verify.odb
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="