#!/bin/bash
echo "=== Exporting Audit Revenue Integrity Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
echo "Capturing final state..."
take_screenshot "/tmp/task_final.png"

# Check if ODB file exists and was modified
ODB_PATH="/home/ga/chinook.odb"
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE=0

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    ODB_MTIME=$(stat -c %Y "$ODB_PATH")
    
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# Check if LO is running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "odb_path": "$ODB_PATH",
    "sqlite_ground_truth_path": "/tmp/chinook_task.sqlite",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy ground truth SQLite to a temp location readable by copy_from_env if needed
# (Permissions usually allow reading from /tmp, but explicit copy helps)
cp /tmp/chinook_task.sqlite /tmp/ground_truth.sqlite
chmod 666 /tmp/ground_truth.sqlite

echo "Export complete."
cat /tmp/task_result.json