#!/bin/bash
echo "=== Exporting add_constraints task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check ODB modification
ODB_PATH="/home/ga/chinook.odb"
ODB_MODIFIED="false"
if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 2. Extract database script from ODB (it's a zip file)
# The 'database/script' file inside the ODB contains the HSQLDB DDL/DML log
EXTRACT_DIR="/tmp/chinook_extract"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

SCRIPT_EXPORTED="false"
if [ -f "$ODB_PATH" ]; then
    echo "Extracting database/script from ODB..."
    if unzip -q "$ODB_PATH" "database/script" -d "$EXTRACT_DIR"; then
        cp "$EXTRACT_DIR/database/script" /tmp/database_script.txt
        chmod 644 /tmp/database_script.txt
        SCRIPT_EXPORTED="true"
        echo "Database script extracted successfully."
    else
        echo "Failed to extract database/script."
    fi
else
    echo "ODB file not found at $ODB_PATH"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_modified": $ODB_MODIFIED,
    "script_exported": $SCRIPT_EXPORTED,
    "script_path": "/tmp/database_script.txt",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="