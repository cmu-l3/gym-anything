#!/bin/bash
echo "=== Exporting Cumulative Revenue Views Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_PATH="/home/ga/chinook.odb"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application was running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Check if ODB file was modified
ODB_MODIFIED="false"
if [ -f "$ODB_PATH" ]; then
    CURRENT_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
else
    ODB_SIZE="0"
fi

# Extract the HSQLDB script file from the ODB zip archive
# This file contains the schema definitions (CREATE VIEW statements)
EXTRACTED_SCRIPT_PATH="/tmp/extracted_hsqldb_script.sql"
rm -f "$EXTRACTED_SCRIPT_PATH"

if [ -f "$ODB_PATH" ]; then
    echo "Extracting database script from ODB..."
    # libreoffice base ODB files are zip archives. 
    # The schema is stored in 'database/script'
    unzip -p "$ODB_PATH" "database/script" > "$EXTRACTED_SCRIPT_PATH" 2>/dev/null || echo "Failed to extract script"
fi

SCRIPT_EXISTS="false"
if [ -f "$EXTRACTED_SCRIPT_PATH" ] && [ -s "$EXTRACTED_SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_modified": $ODB_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "script_extracted": $SCRIPT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also make the extracted script available for the verifier
if [ "$SCRIPT_EXISTS" = "true" ]; then
    chmod 666 "$EXTRACTED_SCRIPT_PATH" 2>/dev/null || sudo chmod 666 "$EXTRACTED_SCRIPT_PATH"
fi

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="