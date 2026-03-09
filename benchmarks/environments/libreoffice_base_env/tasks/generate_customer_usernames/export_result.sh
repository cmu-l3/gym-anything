#!/bin/bash
echo "=== Exporting generate_customer_usernames result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Kill LibreOffice to ensure HSQLDB flushes buffers to disk
# This is critical because HSQLDB (embedded) writes the .script file on shutdown/save
kill_libreoffice

# 3. Check if ODB file was modified
ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"
ODB_SIZE=0

if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Extract the HSQLDB script file from the ODB archive
# The ODB file is a ZIP containing database/script
SCRIPT_EXPORT_PATH="/tmp/hsqldb_script.sql"
rm -f "$SCRIPT_EXPORT_PATH"

if [ -f "$ODB_PATH" ]; then
    echo "Extracting database script from ODB..."
    unzip -p "$ODB_PATH" database/script > "$SCRIPT_EXPORT_PATH" 2>/dev/null || echo "Failed to extract script"
fi

SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
if [ -f "$SCRIPT_EXPORT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c %s "$SCRIPT_EXPORT_PATH")
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "odb_size": $ODB_SIZE,
    "script_extracted": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "script_path": "$SCRIPT_EXPORT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"