#!/bin/bash
echo "=== Exporting merge_person_data result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (before killing app)
take_screenshot /tmp/task_final.png

# 2. Check if LibreOffice is running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# 3. Gracefully close LibreOffice to ensure data is flushed to the ODB file
# This is critical for HSQLDB embedded which writes on shutdown/save
kill_libreoffice

# 4. Check ODB modification
ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 5. Extract the HSQLDB script from the ODB (ZIP) file
# The 'database/script' file inside the ODB contains all DDL (CREATE) and DML (INSERT)
# statements for the embedded database.
EXTRACT_DIR=$(mktemp -d)
SCRIPT_EXPORT_PATH="/tmp/hsqldb_script.sql"

if [ -f "$ODB_PATH" ]; then
    echo "Extracting ODB content..."
    unzip -q "$ODB_PATH" "database/script" -d "$EXTRACT_DIR" 2>/dev/null || true
    
    if [ -f "$EXTRACT_DIR/database/script" ]; then
        cp "$EXTRACT_DIR/database/script" "$SCRIPT_EXPORT_PATH"
        echo "HSQLDB script extracted to $SCRIPT_EXPORT_PATH"
    else
        echo "WARNING: Could not find database/script in ODB file"
        touch "$SCRIPT_EXPORT_PATH"
    fi
else
    echo "WARNING: ODB file not found"
    touch "$SCRIPT_EXPORT_PATH"
fi

# Clean up temp dir
rm -rf "$EXTRACT_DIR"

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "odb_exists": $([ -f "$ODB_PATH" ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png",
    "hsqldb_script_path": "$SCRIPT_EXPORT_PATH"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="