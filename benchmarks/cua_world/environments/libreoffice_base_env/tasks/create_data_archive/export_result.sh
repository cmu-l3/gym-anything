#!/bin/bash
echo "=== Exporting create_data_archive results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (before killing app)
take_screenshot /tmp/task_final.png

# 2. Gracefully close LibreOffice to ensure buffers are flushed to the ODB file
# This is critical for HSQLDB embedded which writes to the .script file inside the zip on save/exit
echo "Closing LibreOffice to flush changes..."
pkill -f "soffice" || true
sleep 3
pkill -9 -f "soffice" || true
sleep 1

# 3. Gather file statistics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_PATH="/home/ga/chinook.odb"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c%s "$ODB_PATH")
    ODB_MTIME=$(stat -c%Y "$ODB_PATH")
    
    # Check if modified
    INITIAL_MD5=$(cat /tmp/initial_odb_checksum.txt 2>/dev/null || echo "")
    CURRENT_MD5=$(md5sum "$ODB_PATH" | awk '{print $1}')
    
    if [ "$INITIAL_MD5" != "$CURRENT_MD5" ]; then
        ODB_MODIFIED="true"
    else
        ODB_MODIFIED="false"
    fi
else
    ODB_EXISTS="false"
    ODB_SIZE=0
    ODB_MTIME=0
    ODB_MODIFIED="false"
fi

# 4. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "odb_exists": $ODB_EXISTS,
    "odb_size": $ODB_SIZE,
    "odb_mtime": $ODB_MTIME,
    "odb_modified": $ODB_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "database_path": "$ODB_PATH",
    "ground_truth_path": "/tmp/ground_truth.json"
}
EOF

# Ensure permissions for copy_from_env
chmod 644 /tmp/task_result.json
chmod 644 /tmp/ground_truth.json
chmod 644 /home/ga/chinook.odb

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="