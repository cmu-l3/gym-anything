#!/bin/bash
set -e
echo "=== Exporting add_visit_purpose_category results ==="

source /workspace/scripts/task_utils.sh

# Record export timestamp
EXPORT_TIME=$(date +%s)
TASK_START=$(cat /tmp/add_visit_purpose_start_time 2>/dev/null || echo "0")

# 1. Check if the agent created the confirmation screenshot
CONFIRMATION_IMG="/home/ga/Documents/visit_purpose_confirmation.png"
CONFIRMATION_EXISTS="false"
CONFIRMATION_VALID="false"

if [ -f "$CONFIRMATION_IMG" ]; then
    CONFIRMATION_EXISTS="true"
    # Check timestamp to ensure it was created during the task
    IMG_TIME=$(stat -c %Y "$CONFIRMATION_IMG" 2>/dev/null || echo "0")
    if [ "$IMG_TIME" -ge "$TASK_START" ]; then
        CONFIRMATION_VALID="true"
    fi
fi

# 2. Check Database for the new record
# We use 'strings' to grep the binary MDB file for the text "Facility Maintenance"
# This is a robust way to verify persistence without needing specific ODBC drivers
DB_FOUND="false"
STRING_FOUND_IN_DB="false"

# Re-locate DB file
DB_FILE=$(find /home/ga/.wine/drive_c -iname "LobbyTrack.mdb" -o -iname "Lobby.mdb" -o -iname "*.mdb" 2>/dev/null | grep -v "Sample" | head -1)

if [ -z "$DB_FILE" ]; then
    DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" 2>/dev/null | head -1)
fi

if [ -n "$DB_FILE" ] && [ -f "$DB_FILE" ]; then
    DB_FOUND="true"
    # Force flush changes to disk if possible (sync)
    sync
    
    # Check for exact string match (case insensitive)
    # We look for "Facility Maintenance"
    if strings "$DB_FILE" | grep -qi "Facility Maintenance"; then
        STRING_FOUND_IN_DB="true"
    fi
fi

# 3. Take final state screenshot (system captured)
take_screenshot /tmp/task_final.png

# 4. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "export_time": $EXPORT_TIME,
    "confirmation_screenshot_exists": $CONFIRMATION_EXISTS,
    "confirmation_screenshot_valid": $CONFIRMATION_VALID,
    "confirmation_path": "$CONFIRMATION_IMG",
    "db_found": $DB_FOUND,
    "db_path": "$DB_FILE",
    "string_found_in_db": $STRING_FOUND_IN_DB,
    "initial_db_state": "$(cat /tmp/db_initial_check.txt 2>/dev/null || echo 'unknown')",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="