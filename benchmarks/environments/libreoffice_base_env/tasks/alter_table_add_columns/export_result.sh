#!/bin/bash
set -e
echo "=== Exporting alter_table_add_columns results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot before closing app
take_screenshot /tmp/task_final.png

# 2. gracefully close LibreOffice to ensure HSQLDB flushes changes to disk
# (HSQLDB embedded only writes the .script file back to the zip on shutdown/save)
echo "Closing LibreOffice to flush database changes..."
kill_libreoffice
sleep 2

# 3. Gather timestamps and file info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_PATH="/home/ga/chinook.odb"

if [ -f "$ODB_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$ODB_PATH")
    FILE_SIZE=$(stat -c %s "$ODB_PATH")
    
    # Check if file was modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        MODIFIED="true"
    else
        MODIFIED="false"
    fi
else
    FILE_EXISTS="false"
    MODIFIED="false"
    FILE_SIZE="0"
fi

# 4. Copy the ODB file to a temp location with a known name for the verifier
# (The verifier will use copy_from_env to retrieve this)
cp "$ODB_PATH" /tmp/result_chinook.odb 2>/dev/null || true
chmod 644 /tmp/result_chinook.odb 2>/dev/null || true

# 5. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "odb_exists": $FILE_EXISTS,
    "odb_modified": $MODIFIED,
    "odb_size": $FILE_SIZE,
    "odb_path": "/tmp/result_chinook.odb",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"