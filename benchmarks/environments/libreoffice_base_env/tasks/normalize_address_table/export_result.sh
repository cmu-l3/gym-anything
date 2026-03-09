#!/bin/bash
set -e
echo "=== Exporting Normalize Address Table Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
DB_PATH="/home/ga/chinook.odb"
SUBMITTED_DB="/tmp/submitted_chinook.odb"
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if application is running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi
# Gracefully close LibreOffice to ensure buffers are flushed to disk
kill_libreoffice

# 3. Check database file status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$DB_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DB_PATH")
    FILE_MTIME=$(stat -c %Y "$DB_PATH")
    
    # Check if modified after start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Copy the database to a temp location for extraction/verification
    cp "$DB_PATH" "$SUBMITTED_DB"
    chmod 644 "$SUBMITTED_DB"
fi

# 4. Create result JSON
# We include metadata about the file to help the verifier, 
# but the verifier will analyze the ODB content itself.
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "db_exists": $FILE_EXISTS,
    "db_modified": $FILE_MODIFIED,
    "db_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "submitted_db_path": "$SUBMITTED_DB"
}
EOF

# Set permissions so the host can read it
chmod 666 "$RESULT_JSON"
chmod 666 "/tmp/task_final.png" 2>/dev/null || true

echo "Result exported to $RESULT_JSON"
echo "=== Export complete ==="