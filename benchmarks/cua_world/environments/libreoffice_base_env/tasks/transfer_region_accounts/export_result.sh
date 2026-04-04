#!/bin/bash
# Export results for transfer_region_accounts task
set -e

echo "=== Exporting transfer_region_accounts results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot of the application state
take_screenshot /tmp/task_final.png

# 2. Kill LibreOffice to ensure HSQLDB flushes changes to the ODB file
# (HSQLDB embedded only saves to the .script file inside the .odb zip on shutdown/save)
kill_libreoffice

# 3. Check for ODB file modification
ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_MODIFIED="false"

if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 4. Copy the ODB file for the verifier to inspect
# (The verifier needs to unzip it and parse database/script)
cp "$ODB_PATH" /tmp/chinook_result.odb
chmod 644 /tmp/chinook_result.odb

# 5. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "odb_modified": $ODB_MODIFIED,
    "odb_path": "/tmp/chinook_result.odb",
    "task_timestamp": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"