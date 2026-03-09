#!/bin/bash
set -e
echo "=== Exporting create_playlist_stats_query results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (before killing app)
take_screenshot /tmp/task_final.png

# 2. Check if LibreOffice is running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# 3. Gracefully close LibreOffice to ensure ODB is saved/flushed
# Using wmctrl to close window is safer than kill for saving changes if user forgot to save,
# but usually we rely on user saving. We'll just kill to force flush of zip archives if open.
kill_libreoffice

# 4. Extract content.xml from the ODB file for verification
# ODB is a zip file. We need content.xml to read the saved queries.
rm -rf /tmp/odb_extract
mkdir -p /tmp/odb_extract

ODB_PATH="/home/ga/chinook.odb"
ODB_EXISTS="false"
ODB_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    
    # Check modification time
    ODB_MTIME=$(stat -c %Y "$ODB_PATH")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi

    # Extract content.xml
    if unzip -q "$ODB_PATH" content.xml -d /tmp/odb_extract; then
        echo "Extracted content.xml successfully."
    else
        echo "Failed to extract content.xml (possibly corrupt ODB)."
    fi
fi

# 5. Prepare results for export
# We need to export:
# - content.xml (to parse the query definition)
# - task_result.json (metadata)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "content_xml_path": "/tmp/odb_extract/content.xml"
}
EOF

# Move JSON to accessible location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Ensure content.xml is readable
if [ -f /tmp/odb_extract/content.xml ]; then
    chmod 666 /tmp/odb_extract/content.xml
fi

echo "Export complete. Result saved to /tmp/task_result.json"