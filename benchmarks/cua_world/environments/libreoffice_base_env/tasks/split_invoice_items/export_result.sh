#!/bin/bash
# Export script for split_invoice_items

echo "=== Exporting Split Invoice Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot of the application state (before killing it)
take_screenshot /tmp/task_final.png

# 2. Kill LibreOffice to ensure all data is flushed to disk and file lock is released
kill_libreoffice

# 3. Check file modification
ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"

if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Prepare result for verifier
# We need to copy the ODB file to a temp location for the verifier to pull
cp "$ODB_PATH" /tmp/result.odb 2>/dev/null || true

# 5. Create JSON metadata
cat > /tmp/task_result.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "file_modified": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "odb_path": "/tmp/result.odb"
}
EOF

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="