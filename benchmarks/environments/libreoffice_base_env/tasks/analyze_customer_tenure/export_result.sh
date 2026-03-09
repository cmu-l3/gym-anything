#!/bin/bash
echo "=== Exporting analyze_customer_tenure result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Path to the database file
DB_PATH="/home/ga/chinook.odb"

# Check ODB file status
if [ -f "$DB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$DB_PATH" 2>/dev/null || echo "0")
    ODB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
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
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "database_path": "$DB_PATH"
}
EOF

# Save result JSON
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy the ODB file to /tmp for easier extraction by verifier if needed
# (Though copy_from_env can grab it from home, putting it in tmp is safer permission-wise)
if [ "$ODB_EXISTS" = "true" ]; then
    cp "$DB_PATH" /tmp/chinook_result.odb
    chmod 666 /tmp/chinook_result.odb
fi

echo "Export complete. Result saved to /tmp/task_result.json"