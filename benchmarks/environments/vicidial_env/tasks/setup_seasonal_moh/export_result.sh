#!/bin/bash
echo "=== Exporting setup_seasonal_moh result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query Database for MOH Class Configuration
echo "Querying database..."
DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT moh_id, moh_name, random_order, active FROM vicidial_music_on_hold WHERE moh_id='HOLIDAY25'" 2>/dev/null || echo "")

MOH_EXISTS="false"
MOH_ID=""
MOH_NAME=""
RANDOM_ORDER=""
ACTIVE=""

if [ -n "$DB_RESULT" ]; then
    MOH_EXISTS="true"
    MOH_ID=$(echo "$DB_RESULT" | awk '{print $1}')
    # Name might contain spaces, so we cut specific fields
    MOH_NAME=$(echo "$DB_RESULT" | cut -f2)
    RANDOM_ORDER=$(echo "$DB_RESULT" | cut -f3)
    ACTIVE=$(echo "$DB_RESULT" | cut -f4)
fi

# 2. Check File System inside Docker for Uploaded Files
echo "Checking filesystem..."
# Directory should be /var/lib/asterisk/mohmp3/HOLIDAY25
# We list files in that directory
FILES_LIST=$(docker exec vicidial sh -c "ls -1 /var/lib/asterisk/mohmp3/HOLIDAY25 2>/dev/null" || echo "")

FILE_JINGLE_EXISTS="false"
FILE_OFFER_EXISTS="false"
FILE_COUNT=0

if [ -n "$FILES_LIST" ]; then
    FILE_COUNT=$(echo "$FILES_LIST" | wc -l)
    if echo "$FILES_LIST" | grep -q "holiday_jingle"; then FILE_JINGLE_EXISTS="true"; fi
    if echo "$FILES_LIST" | grep -q "seasonal_offer"; then FILE_OFFER_EXISTS="true"; fi
fi

# 3. Check if Admin Interface was used (Firefox running)
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "moh_exists": $MOH_EXISTS,
    "moh_config": {
        "id": "$MOH_ID",
        "name": "$MOH_NAME",
        "random_order": "$RANDOM_ORDER",
        "active": "$ACTIVE"
    },
    "files": {
        "directory_found": $([ -n "$FILES_LIST" ] && echo "true" || echo "false"),
        "file_count": $FILE_COUNT,
        "jingle_uploaded": $FILE_JINGLE_EXISTS,
        "offer_uploaded": $FILE_OFFER_EXISTS,
        "raw_list": "$(echo $FILES_LIST | tr '\n' ',')"
    },
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="