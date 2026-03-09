#!/bin/bash
set -e
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (before killing app)
take_screenshot /tmp/task_final.png

# 2. Kill LibreOffice to ensure buffers are flushed to the ODB file
# LibreOffice updates the ODB (ZIP) file upon save/exit.
kill_libreoffice
sleep 2

# 3. Extract the HSQLDB script from the ODB file
# The ODB file is a ZIP archive. The schema/data is in 'database/script'.
ODB_PATH="/home/ga/chinook.odb"
EXTRACT_DIR="/tmp/odb_extract"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

if [ -f "$ODB_PATH" ]; then
    echo "Extracting ODB file..."
    unzip -q "$ODB_PATH" -d "$EXTRACT_DIR" || echo "Warning: Unzip had issues"
    
    if [ -f "$EXTRACT_DIR/database/script" ]; then
        echo "Found database script."
        cp "$EXTRACT_DIR/database/script" /tmp/database_script.sql
    else
        echo "ERROR: database/script not found in ODB archive"
    fi
else
    echo "ERROR: ODB file not found at $ODB_PATH"
fi

# 4. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED_DURING_TASK="false"
if [ -f "$ODB_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# 5. Create JSON result
# We save relevant info for the verifier
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "odb_exists": $([ -f "$ODB_PATH" ] && echo "true" || echo "false"),
    "odb_modified": $FILE_MODIFIED_DURING_TASK,
    "script_extracted": $([ -f "/tmp/database_script.sql" ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Clean up extract dir
rm -rf "$EXTRACT_DIR"

echo "=== Export complete ==="