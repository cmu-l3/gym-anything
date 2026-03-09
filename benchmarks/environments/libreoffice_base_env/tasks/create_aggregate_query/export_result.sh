#!/bin/bash
set -e
echo "=== Exporting create_aggregate_query results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (before killing app)
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# 2. Gracefully close LibreOffice to ensure ODB is saved/flushed
# Using xdotool to try Ctrl+Q first
DISPLAY=:1 xdotool key ctrl+q 2>/dev/null || true
sleep 2
# Then confirm save if prompted (Enter)
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 2

# 3. Force kill if still running
kill_libreoffice

# 4. Gather result data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")

ODB_PATH="/home/ga/chinook.odb"
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE=0
ODB_MTIME=0

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    ODB_MTIME=$(stat -c %Y "$ODB_PATH")
    
    # Check modification time
    if [ "$ODB_MTIME" -gt "$INITIAL_MTIME" ]; then
        ODB_MODIFIED="true"
    fi
fi

SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_mtime": $ODB_MTIME,
    "odb_size": $ODB_SIZE,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 6. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="