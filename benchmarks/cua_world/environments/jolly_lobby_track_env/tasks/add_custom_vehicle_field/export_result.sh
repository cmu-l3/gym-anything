#!/bin/bash
echo "=== Exporting add_custom_vehicle_field results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/add_custom_vehicle_field_start_time 2>/dev/null || echo "0")

# 1. Check Screenshot Evidence
SCREENSHOT_PATH="/home/ga/Desktop/vehicle_field_verification.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    # Check if created during task
    FILE_TIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        SCREENSHOT_VALID="true"
    fi
fi

# 2. Check Database Persistence (via string search since we don't have mdb-tools guaranteed)
# We look for the unique license plate in the database file
DB_STRING_FOUND="false"
VISITOR_NAME_FOUND="false"

# Find the database file (usually an .mdb or .sdf file in the installation or ProgramData)
# Search typical paths
DB_FILES=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" -o -name "*.ldb" 2>/dev/null)

for db_file in $DB_FILES; do
    # Use strings to search binary file
    if strings "$db_file" | grep -q "7XKP392"; then
        DB_STRING_FOUND="true"
        echo "Found license plate in: $db_file"
    fi
    if strings "$db_file" | grep -i "Mendez" | grep -i "Carlos"; then
        VISITOR_NAME_FOUND="true"
        echo "Found visitor name in: $db_file"
    fi
done

# 3. Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 4. Check if app is still running
APP_RUNNING=$(pgrep -f "Lobby" > /dev/null && echo "true" || echo "false")

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid_timestamp": $SCREENSHOT_VALID,
    "database_license_plate_found": $DB_STRING_FOUND,
    "database_visitor_found": $VISITOR_NAME_FOUND,
    "app_running": $APP_RUNNING
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="