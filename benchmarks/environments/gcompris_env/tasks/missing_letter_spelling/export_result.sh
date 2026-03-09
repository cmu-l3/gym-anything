#!/bin/bash
set -e

echo "=== Exporting Missing Letter Spelling task results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# ==============================================================================
# DATA EXPORT
# ==============================================================================
# We need to export the sqlite database to analyze progress programmatically.
# The container environment might not have python/sqlite access inside the verification
# script directly if we don't copy it out.

DB_PATH="/home/ga/.local/share/GCompris/gcompris-qt.db"
DB_EXPORT_PATH="/tmp/gcompris_export.db"
DB_EXISTS="false"

if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    # Copy DB to a temp location to avoid locking issues and for export
    cp "$DB_PATH" "$DB_EXPORT_PATH"
    chmod 666 "$DB_EXPORT_PATH"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "db_exists": $DB_EXISTS,
    "db_path": "$DB_EXPORT_PATH",
    "initial_db_count": $(cat /tmp/initial_db_count.txt 2>/dev/null || echo "0"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to expected location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="