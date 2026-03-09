#!/bin/bash
echo "=== Exporting create_audit_triggers result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot of the application state (before killing it)
take_screenshot /tmp/task_final.png

# 2. Kill LibreOffice to ensure buffers are flushed and file lock is released
# This is critical for ODB files as they are ZIP archives that get updated on close/save
kill_libreoffice

# 3. Prepare extraction directory
EXTRACT_DIR="/tmp/odb_extract"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

# 4. Check if ODB file exists and verify modification
ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"
ODB_EXISTS="false"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # 5. Unzip the ODB file to access the internal HSQLDB script
    # The 'database/script' file contains the DDL and INSERT statements
    echo "Extracting ODB file..."
    unzip -q "$ODB_PATH" "database/script" -d "$EXTRACT_DIR" 2>/dev/null || echo "Failed to unzip ODB"
else
    echo "ERROR: chinook.odb not found"
fi

# 6. Check if script file was extracted
SCRIPT_PATH="$EXTRACT_DIR/database/script"
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    cp "$SCRIPT_PATH" /tmp/hsqldb_script.txt
    chmod 644 /tmp/hsqldb_script.txt
fi

# 7. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "odb_exists": $ODB_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "script_extracted": $SCRIPT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result export complete."
cat /tmp/task_result.json