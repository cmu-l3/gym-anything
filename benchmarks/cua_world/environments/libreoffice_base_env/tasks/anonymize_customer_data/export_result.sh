#!/bin/bash
echo "=== Exporting Anonymize Customer Data Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot of the UI (Agent might be viewing the table)
take_screenshot /tmp/task_final.png

# 2. Kill LibreOffice to ensure data is flushed to ODB file
# (HSQLDB embedded only writes fully on close/save)
kill_libreoffice

# 3. Process the ODB file
# The ODB file is a ZIP archive. The actual data is in 'database/script' (for HSQLDB).
# We extract this script file to analyze the INSERT statements.

ODB_PATH="/home/ga/chinook.odb"
EXPORT_DIR="/tmp/export_data"
mkdir -p "$EXPORT_DIR"

if [ -f "$ODB_PATH" ]; then
    echo "Extracting database script from ODB..."
    # Unzip specific file 'database/script' to temp dir
    unzip -p "$ODB_PATH" database/script > "$EXPORT_DIR/database_script.sql"
    
    # Check if extraction was successful
    if [ -s "$EXPORT_DIR/database_script.sql" ]; then
        echo "Database script extracted successfully ($(stat -c%s "$EXPORT_DIR/database_script.sql") bytes)."
        SCRIPT_EXISTS="true"
    else
        echo "ERROR: Extracted script is empty."
        SCRIPT_EXISTS="false"
    fi
    
    # Check modification time
    ODB_MTIME=$(stat -c %Y "$ODB_PATH")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    echo "ERROR: chinook.odb not found."
    SCRIPT_EXISTS="false"
    FILE_MODIFIED="false"
fi

# 4. Create metadata JSON
cat > "$EXPORT_DIR/task_result.json" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": true,
    "odb_modified": $FILE_MODIFIED,
    "script_extracted": $SCRIPT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Prepare files for the verifier
# We need to expose the JSON and the extracted SQL script
cp "$EXPORT_DIR/task_result.json" /tmp/task_result.json
cp "$EXPORT_DIR/database_script.sql" /tmp/database_script.sql 2>/dev/null || true

# Set permissions
chmod 644 /tmp/task_result.json 2>/dev/null
chmod 644 /tmp/database_script.sql 2>/dev/null

echo "Export complete. Result and SQL script ready for verification."