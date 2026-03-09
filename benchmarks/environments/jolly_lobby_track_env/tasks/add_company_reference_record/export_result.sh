#!/bin/bash
echo "=== Exporting Add Company Reference Record Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# VERIFICATION 1: DATABASE INSPECTION
# ==============================================================================
# Locate the database file again
DB_FILE=$(find /home/ga/.wine/drive_c -iname "LobbyTrack*.mdb" -o -iname "Sample*.mdb" 2>/dev/null | head -1)

DB_FOUND="false"
RECORD_FOUND="false"
CITY_FOUND="false"
DB_MODIFIED="false"
DB_SIZE="0"

if [ -f "$DB_FILE" ]; then
    DB_FOUND="true"
    DB_SIZE=$(stat -c %s "$DB_FILE")
    
    # Check modification time
    DB_MTIME=$(stat -c %Y "$DB_FILE")
    INITIAL_MTIME=$(cat /tmp/initial_db_mtime.txt 2>/dev/null || echo "0")
    
    if [ "$DB_MTIME" -gt "$INITIAL_MTIME" ] && [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi

    # Check content using 'strings' to read binary Access/SDF file
    # We check for both ASCII and UTF-16LE (common in Windows DBs)
    
    # Check for Company Name "Aramark"
    if strings "$DB_FILE" | grep -iq "Aramark" || strings -el "$DB_FILE" | grep -iq "Aramark"; then
        RECORD_FOUND="true"
    fi
    
    # Check for City "Philadelphia"
    if strings "$DB_FILE" | grep -iq "Philadelphia" || strings -el "$DB_FILE" | grep -iq "Philadelphia"; then
        CITY_FOUND="true"
    fi
    
    echo "Database analysis: Found=$DB_FOUND, Modified=$DB_MODIFIED, Record=$RECORD_FOUND, City=$CITY_FOUND"
fi

# ==============================================================================
# VERIFICATION 2: APP STATE
# ==============================================================================
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# ==============================================================================
# EXPORT JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_found": $DB_FOUND,
    "db_path": "$DB_FILE",
    "db_modified_during_task": $DB_MODIFIED,
    "record_name_found": $RECORD_FOUND,
    "record_city_found": $CITY_FOUND,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="