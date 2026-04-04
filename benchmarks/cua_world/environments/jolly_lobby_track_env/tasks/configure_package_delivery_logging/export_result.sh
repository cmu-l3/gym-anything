#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# DATABASE / FILE INSPECTION
# ==============================================================================
# Jolly Lobby Track typically stores data in an Access .mdb file or similar in the Wine prefix.
# We will search for the database file and grep it for the expected strings.
# This is a heuristic approach since we might not have mdb-tools installed.

echo "Searching for database files..."
DB_FILES=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" -o -name "*.db" -o -name "*.xml" 2>/dev/null)

# Strings to look for
TARGET_GROUP="Deliveries"
TARGET_FIELD="Tracking Number"
TARGET_TRACKING="1Z999AA10123456784"
TARGET_NAME="FedEx"

GROUP_FOUND="false"
FIELD_FOUND="false"
TRACKING_FOUND="false"
NAME_FOUND="false"

# Helper function to search in file
search_in_file() {
    local file="$1"
    local term="$2"
    # Use grep -a to treat binary files as text
    if grep -aq "$term" "$file"; then
        return 0
    else
        return 1
    fi
}

echo "Inspecting database files for evidence..."
for db in $DB_FILES; do
    echo "Checking $db..."
    
    if search_in_file "$db" "$TARGET_GROUP"; then
        GROUP_FOUND="true"
        echo "  Found group '$TARGET_GROUP'"
    fi
    
    if search_in_file "$db" "$TARGET_FIELD"; then
        FIELD_FOUND="true"
        echo "  Found field '$TARGET_FIELD'"
    fi
    
    if search_in_file "$db" "$TARGET_TRACKING"; then
        TRACKING_FOUND="true"
        echo "  Found tracking number '$TARGET_TRACKING'"
    fi
    
    if search_in_file "$db" "$TARGET_NAME"; then
        NAME_FOUND="true"
        echo "  Found name '$TARGET_NAME'"
    fi
done

# Also check if the DB file was modified during the task
DB_MODIFIED_DURING_TASK="false"
MOST_RECENT_DB=""
MOST_RECENT_TIME=0

for db in $DB_FILES; do
    MTIME=$(stat -c %Y "$db" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED_DURING_TASK="true"
        if [ "$MTIME" -gt "$MOST_RECENT_TIME" ]; then
            MOST_RECENT_TIME=$MTIME
            MOST_RECENT_DB="$db"
        fi
    fi
done

echo "Database modified during task: $DB_MODIFIED_DURING_TASK"

# Check if application is running
APP_RUNNING=$(pgrep -f "Lobby" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "group_found_in_db": $GROUP_FOUND,
    "field_found_in_db": $FIELD_FOUND,
    "tracking_found_in_db": $TRACKING_FOUND,
    "name_found_in_db": $NAME_FOUND,
    "db_modified_during_task": $DB_MODIFIED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="