#!/bin/bash
echo "=== Exporting Configure Contractor Group Result ==="

source /workspace/scripts/task_utils.sh

# Record final state
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/configure_contractor_group_start_time 2>/dev/null || echo "0")

# 1. Take final screenshot (Critical for VLM verification of UI)
take_screenshot /tmp/task_final.png

# 2. Check Database/Config Changes
# We look for the string "Contractors" in the database files
echo "Scanning for configuration changes..."
CONFIG_MODIFIED="false"
CONTRACTORS_FOUND_IN_DB="false"
MEMBERS_FOUND_IN_DB="false"

# Find database files that have been modified since task start
# Jolly Lobby Track typically uses Access (.mdb) or Compact SQL (.sdf)
DB_FILES=$(find /home/ga/.wine/drive_c -type f \( -name "*.mdb" -o -name "*.sdf" -o -name "*.xml" \) -newermt "@$TASK_START" 2>/dev/null)

if [ -n "$DB_FILES" ]; then
    CONFIG_MODIFIED="true"
    echo "Modified config files found:"
    echo "$DB_FILES"
    
    # Check content of modified files using strings (binary safe)
    for db in $DB_FILES; do
        if strings "$db" | grep -q "Contractors"; then
            CONTRACTORS_FOUND_IN_DB="true"
            echo "Found 'Contractors' in $db"
        fi
        if strings "$db" | grep -q "Members"; then
            MEMBERS_FOUND_IN_DB="true"
        fi
    done
else
    # If no file modified, check all DBs just in case timestamp logic failed
    # (sometimes Wine timestamps are tricky)
    ALL_DB_FILES=$(find /home/ga/.wine/drive_c -type f \( -name "*.mdb" -o -name "*.sdf" \))
    for db in $ALL_DB_FILES; do
        if strings "$db" | grep -q "Contractors"; then
            CONTRACTORS_FOUND_IN_DB="true"
            # But we can't be sure it was modified *during* task without timestamp
            # We rely on the fact that "Contractors" shouldn't be there initially
        fi
    done
fi

# 3. Check App Status
APP_RUNNING=$(pgrep -f "LobbyTrack" > /dev/null && echo "true" || echo "false")

# 4. Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_files_modified": $CONFIG_MODIFIED,
    "contractors_string_found": $CONTRACTORS_FOUND_IN_DB,
    "members_string_found": $MEMBERS_FOUND_IN_DB,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="