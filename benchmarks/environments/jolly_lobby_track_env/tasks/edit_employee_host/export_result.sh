#!/bin/bash
echo "=== Exporting edit_employee_host result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check App Status
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Analyze Database
# We need to verify if the changes were saved to the DB.
# Since we can't easily parse MDB/SDF on Linux without tools,
# we will use 'strings' to extract text and look for the new values.
# This is a robust way to check if the data exists in the binary file.

DB_FILE=$(cat /tmp/db_location.txt 2>/dev/null || find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" 2>/dev/null | head -1)

DB_MODIFIED="false"
DB_STRINGS_FILE="/tmp/db_strings_dump.txt"
NEW_VALUES_FOUND_COUNT=0
OLD_VALUES_FOUND_COUNT=0

if [ -f "$DB_FILE" ]; then
    # Check modification time
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    # Dump strings (UTF-16 LE is common in Windows DBs, usually 'strings' handles ASCII/UTF-8)
    # We'll try extracting both encoding types just in case
    strings "$DB_FILE" > "$DB_STRINGS_FILE"
    strings -e l "$DB_FILE" >> "$DB_STRINGS_FILE" 2>/dev/null || true
    
    # Check for new values
    if grep -qi "Product Development" "$DB_STRINGS_FILE"; then ((NEW_VALUES_FOUND_COUNT++)); fi
    if grep -q "555-867-5309" "$DB_STRINGS_FILE"; then ((NEW_VALUES_FOUND_COUNT++)); fi
    if grep -qi "s.mitchell@proddev.example.com" "$DB_STRINGS_FILE"; then ((NEW_VALUES_FOUND_COUNT++)); fi
    
    # Check for old values (to see if they were overwritten or if duplicate records exist)
    # Note: Access DBs often don't delete immediately, just mark as deleted, so old values might still exist.
    # Verification should focus on the PRESENCE of NEW values.
    if grep -qi "sarah.mitchell@marketing.example.com" "$DB_STRINGS_FILE"; then ((OLD_VALUES_FOUND_COUNT++)); fi

    echo "Database analysis:"
    echo "  File: $DB_FILE"
    echo "  Modified: $DB_MODIFIED"
    echo "  New Values Found: $NEW_VALUES_FOUND_COUNT / 3"
else
    echo "Error: Database file not found during export."
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_running": $APP_RUNNING,
    "db_found": $([ -f "$DB_FILE" ] && echo "true" || echo "false"),
    "db_modified": $DB_MODIFIED,
    "new_values_count": $NEW_VALUES_FOUND_COUNT,
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="