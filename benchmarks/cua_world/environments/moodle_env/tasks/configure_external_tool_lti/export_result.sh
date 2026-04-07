#!/bin/bash
# Export script for Configure External Tool LTI task

echo "=== Exporting Configure External Tool LTI Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
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

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Course ID
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")

# 3. Get Initial Counts
INITIAL_TYPES=$(cat /tmp/initial_lti_types_count 2>/dev/null || echo "0")
INITIAL_INSTANCES=$(cat /tmp/initial_lti_instances_count 2>/dev/null || echo "0")

# 4. Query Current Counts
CURRENT_TYPES=$(moodle_query "SELECT COUNT(*) FROM mdl_lti_types" | tr -d '[:space:]')
CURRENT_INSTANCES=$(moodle_query "SELECT COUNT(*) FROM mdl_lti" | tr -d '[:space:]')

# 5. Check for the Preconfigured Tool (Site Level)
# Look for tool named 'CodePractice Pro'
TOOL_QUERY="SELECT id, name, baseurl, state, timecreated FROM mdl_lti_types WHERE name LIKE '%CodePractice Pro%' ORDER BY id DESC LIMIT 1"
TOOL_DATA=$(moodle_query "$TOOL_QUERY")

TOOL_FOUND="false"
TOOL_ID=""
TOOL_NAME=""
TOOL_URL=""
TOOL_STATE=""
TOOL_TIMECREATED="0"
CONSUMER_KEY=""
SHARED_SECRET=""

if [ -n "$TOOL_DATA" ]; then
    TOOL_FOUND="true"
    TOOL_ID=$(echo "$TOOL_DATA" | cut -f1)
    TOOL_NAME=$(echo "$TOOL_DATA" | cut -f2)
    TOOL_URL=$(echo "$TOOL_DATA" | cut -f3)
    TOOL_STATE=$(echo "$TOOL_DATA" | cut -f4)
    TOOL_TIMECREATED=$(echo "$TOOL_DATA" | cut -f5)
    
    # Get config (Consumer Key and Shared Secret)
    # They are stored in mdl_lti_types_config with names 'resourcekey' and 'password'
    CONSUMER_KEY=$(moodle_query "SELECT value FROM mdl_lti_types_config WHERE typeid=$TOOL_ID AND name='resourcekey'" | tr -d '[:space:]')
    SHARED_SECRET=$(moodle_query "SELECT value FROM mdl_lti_types_config WHERE typeid=$TOOL_ID AND name='password'" | tr -d '[:space:]')
fi

# 6. Check for the Course Activity
# Look for LTI activity named 'Week 3: Python Loops Practice' in CS101
ACTIVITY_QUERY="SELECT id, course, name, typeid, timecreated FROM mdl_lti WHERE course=$COURSE_ID AND name LIKE '%Python Loops Practice%' ORDER BY id DESC LIMIT 1"
ACTIVITY_DATA=$(moodle_query "$ACTIVITY_QUERY")

ACTIVITY_FOUND="false"
ACTIVITY_ID=""
ACTIVITY_NAME=""
ACTIVITY_TYPEID=""
ACTIVITY_TIMECREATED="0"

if [ -n "$ACTIVITY_DATA" ]; then
    ACTIVITY_FOUND="true"
    ACTIVITY_ID=$(echo "$ACTIVITY_DATA" | cut -f1)
    # Course ID checked in query
    ACTIVITY_NAME=$(echo "$ACTIVITY_DATA" | cut -f3)
    ACTIVITY_TYPEID=$(echo "$ACTIVITY_DATA" | cut -f4)
    ACTIVITY_TIMECREATED=$(echo "$ACTIVITY_DATA" | cut -f5)
fi

# Escape for JSON
TOOL_NAME_ESC=$(echo "$TOOL_NAME" | sed 's/"/\\"/g')
TOOL_URL_ESC=$(echo "$TOOL_URL" | sed 's/"/\\"/g')
ACTIVITY_NAME_ESC=$(echo "$ACTIVITY_NAME" | sed 's/"/\\"/g')

# 7. Create JSON Result
TEMP_JSON=$(mktemp /tmp/lti_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_types_count": ${INITIAL_TYPES:-0},
    "current_types_count": ${CURRENT_TYPES:-0},
    "initial_instances_count": ${INITIAL_INSTANCES:-0},
    "current_instances_count": ${CURRENT_INSTANCES:-0},
    "tool_found": $TOOL_FOUND,
    "tool": {
        "id": "${TOOL_ID}",
        "name": "${TOOL_NAME_ESC}",
        "url": "${TOOL_URL_ESC}",
        "state": "${TOOL_STATE}",
        "consumer_key": "${CONSUMER_KEY}",
        "shared_secret": "${SHARED_SECRET}",
        "timecreated": ${TOOL_TIMECREATED:-0}
    },
    "activity_found": $ACTIVITY_FOUND,
    "activity": {
        "id": "${ACTIVITY_ID}",
        "name": "${ACTIVITY_NAME_ESC}",
        "typeid": "${ACTIVITY_TYPEID}",
        "timecreated": ${ACTIVITY_TIMECREATED:-0}
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_external_tool_lti_result.json

echo ""
cat /tmp/configure_external_tool_lti_result.json
echo ""
echo "=== Export Complete ==="