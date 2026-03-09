#!/bin/bash
echo "=== Exporting Standardize Artist Names Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")

# Database Path
DB_PATH="/home/ga/chinook.odb"

# Check database status
if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    DB_SIZE=$(stat -c %s "$DB_PATH" 2>/dev/null || echo "0")
    DB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo "0")
    
    # Check if file was modified (Saved)
    if [ "$DB_MTIME" -gt "$INITIAL_MTIME" ]; then
        DB_MODIFIED="true"
    else
        DB_MODIFIED="false"
    fi
else
    DB_EXISTS="false"
    DB_SIZE="0"
    DB_MTIME="0"
    DB_MODIFIED="false"
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Copy the ODB file to temp for the verifier to access safely
# We rename it to ensure no conflict and specific identification
cp "$DB_PATH" /tmp/submitted_chinook.odb 2>/dev/null || true
chmod 644 /tmp/submitted_chinook.odb 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_exists": $DB_EXISTS,
    "db_modified": $DB_MODIFIED,
    "db_size_bytes": $DB_SIZE,
    "app_was_running": $APP_RUNNING,
    "submitted_db_path": "/tmp/submitted_chinook.odb",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="