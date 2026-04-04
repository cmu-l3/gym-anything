#!/bin/bash
# post_task hook for implement_mood_tagging
echo "=== Exporting implement_mood_tagging result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if ODB file exists and was modified
ODB_PATH="/home/ga/chinook.odb"
FILE_MODIFIED="false"
if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Extract HSQLDB script from ODB for verification
# ODB is a zip file. 'database/script' contains the Schema and often the data (for MEMORY tables).
EXTRACT_DIR="/tmp/odb_extract"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

SCRIPT_EXTRACTED="false"
if [ -f "$ODB_PATH" ]; then
    if unzip -q "$ODB_PATH" "database/script" -d "$EXTRACT_DIR"; then
        echo "HSQLDB script extracted successfully."
        SCRIPT_EXTRACTED="true"
        # Copy to a location accessible for copy_from_env (though we use /tmp anyway)
        cp "$EXTRACT_DIR/database/script" /tmp/hsqldb_script.sql
    else
        echo "Failed to unzip ODB file."
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_modified": $FILE_MODIFIED,
    "script_extracted": $SCRIPT_EXTRACTED,
    "script_path": "/tmp/hsqldb_script.sql",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result to predictable location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="