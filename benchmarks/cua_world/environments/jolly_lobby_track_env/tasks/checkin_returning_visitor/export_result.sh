#!/bin/bash
echo "=== Exporting checkin_returning_visitor result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# Check Database Modification
# ==============================================================================
DB_FILE=$(find /home/ga/.wine/drive_c -name "LobbyTrack.mdb" 2>/dev/null | head -1)
DB_MODIFIED="false"
DB_SIZE_CHANGED="false"

if [ -f "$DB_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$DB_FILE")
    CURRENT_SIZE=$(stat -c %s "$DB_FILE")
    
    INITIAL_MTIME=$(cat /tmp/initial_db_mtime.txt 2>/dev/null || echo "0")
    INITIAL_SIZE=$(cat /tmp/initial_db_size.txt 2>/dev/null || echo "0")
    
    # Check if modified since start
    TASK_START=$(cat /tmp/checkin_returning_visitor_start_time 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    if [ "$CURRENT_SIZE" -ne "$INITIAL_SIZE" ]; then
        DB_SIZE_CHANGED="true"
    fi
    
    echo "DB File: $DB_FILE"
    echo "Modified: $DB_MODIFIED (Time: $CURRENT_MTIME vs Start: $TASK_START)"
    echo "Size Changed: $DB_SIZE_CHANGED ($INITIAL_SIZE -> $CURRENT_SIZE)"
else
    echo "WARNING: Database file not found."
fi

# ==============================================================================
# Create Result JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_modified": $DB_MODIFIED,
    "db_size_changed": $DB_SIZE_CHANGED,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

cat /tmp/task_result.json
echo "=== Export complete ==="