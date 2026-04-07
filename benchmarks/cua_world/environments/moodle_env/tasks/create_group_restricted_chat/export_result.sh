#!/bin/bash
# Export script for Create Group Restricted Chat task

echo "=== Exporting Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"; echo "Result saved to $dest_path"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get Course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')

# 2. Get Group ID for "Project Team Alpha"
GROUP_NAME="Project Team Alpha"
GROUP_ID=$(moodle_query "SELECT id FROM mdl_groups WHERE courseid=$COURSE_ID AND name='$GROUP_NAME'" | tr -d '[:space:]')

# 3. Find the Chat Activity
CHAT_NAME="Alpha Team Coordination"
CHAT_DATA=$(moodle_query "SELECT id, chattime, schedule, keepdays FROM mdl_chat WHERE course=$COURSE_ID AND name='$CHAT_NAME' ORDER BY id DESC LIMIT 1")

CHAT_FOUND="false"
CHAT_ID=""
CHAT_TIME="0"
CHAT_SCHEDULE="0"
CHAT_KEEPDAYS="0"
AVAILABILITY_JSON=""
CM_ID=""
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -n "$CHAT_DATA" ]; then
    CHAT_FOUND="true"
    CHAT_ID=$(echo "$CHAT_DATA" | cut -f1 | tr -d '[:space:]')
    CHAT_TIME=$(echo "$CHAT_DATA" | cut -f2 | tr -d '[:space:]')
    CHAT_SCHEDULE=$(echo "$CHAT_DATA" | cut -f3 | tr -d '[:space:]')
    CHAT_KEEPDAYS=$(echo "$CHAT_DATA" | cut -f4 | tr -d '[:space:]')
    
    # Get Course Module ID and Availability
    # We need the 'chat' module ID first
    MODULE_ID=$(moodle_query "SELECT id FROM mdl_modules WHERE name='chat'" | tr -d '[:space:]')
    
    if [ -n "$MODULE_ID" ]; then
        CM_DATA=$(moodle_query "SELECT id, availability, added FROM mdl_course_modules WHERE course=$COURSE_ID AND module=$MODULE_ID AND instance=$CHAT_ID LIMIT 1")
        if [ -n "$CM_DATA" ]; then
            CM_ID=$(echo "$CM_DATA" | cut -f1 | tr -d '[:space:]')
            AVAILABILITY_JSON=$(echo "$CM_DATA" | cut -f2) # Keep original formatting
            ADDED_TIME=$(echo "$CM_DATA" | cut -f3 | tr -d '[:space:]')
        fi
    fi
fi

# Determine if created during task
CREATED_DURING_TASK="false"
if [ -n "$ADDED_TIME" ] && [ "$ADDED_TIME" -gt "$TASK_START_TIME" ]; then
    CREATED_DURING_TASK="true"
fi

# Escape JSON for inclusion
SAFE_AVAILABILITY_JSON=$(echo "$AVAILABILITY_JSON" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/chat_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "chat_found": $CHAT_FOUND,
    "chat_id": "$CHAT_ID",
    "course_id": "$COURSE_ID",
    "group_id": "$GROUP_ID",
    "chat_time": ${CHAT_TIME:-0},
    "chat_schedule": ${CHAT_SCHEDULE:-0},
    "chat_keepdays": ${CHAT_KEEPDAYS:-0},
    "cm_id": "$CM_ID",
    "availability_json": "$SAFE_AVAILABILITY_JSON",
    "created_during_task": $CREATED_DURING_TASK,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_group_restricted_chat_result.json

echo ""
cat /tmp/create_group_restricted_chat_result.json
echo ""
echo "=== Export Complete ==="