#!/bin/bash
set -e
echo "=== Exporting Bulk Update Corrections Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (before closing app)
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# 2. Force Close LibreOffice
# CRITICAL: HSQLDB embedded databases in LibreOffice only write the full data script
# back to the ODB zip container when the database connection is closed.
# We must ensure the process is terminated to flush changes to disk.
echo "Closing LibreOffice to flush database changes..."
kill_libreoffice

# Wait a moment for file operations to complete
sleep 3

# 3. Gather Task Artifacts
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ODB_PATH="/home/ga/chinook.odb"

# Check ODB file status
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    ODB_MTIME=$(stat -c %Y "$ODB_PATH")
    
    # Check if modified since start
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 4. Create Result JSON
# We don't verify the SQL data here (too complex for bash).
# The verifier.py will pull the .odb file and parse it.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "odb_path": "$ODB_PATH"
}
EOF

# Move result to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved. Verifier will inspect ODB content."
cat /tmp/task_result.json
echo "=== Export complete ==="