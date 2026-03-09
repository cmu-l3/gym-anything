#!/bin/bash
echo "=== Exporting bulk_checkin_expected_group result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if database was modified
DB_PATH="/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track/Database/LobbyTrack.mdb"
# Fallback path if standard install location varies
if [ ! -f "$DB_PATH" ]; then
    DB_PATH=$(find /home/ga/.wine/drive_c -name "*.mdb" | head -n 1)
fi

DB_MODIFIED="false"
DB_SIZE_BYTES=0

if [ -f "$DB_PATH" ]; then
    TASK_START=$(cat /tmp/bulk_checkin_expected_group_start_time 2>/dev/null || echo "0")
    DB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo "0")
    
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    DB_SIZE_BYTES=$(stat -c %s "$DB_PATH" 2>/dev/null || echo "0")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_modified": $DB_MODIFIED,
    "db_path": "$DB_PATH",
    "db_size_bytes": $DB_SIZE_BYTES,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="