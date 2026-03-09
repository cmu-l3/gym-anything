#!/bin/bash
# Export script for SPAN101 Oral Exam Scheduler task

echo "=== Exporting SPAN101 Oral Exam Scheduler Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
if ! type canvas_query &>/dev/null; then
    _get_canvas_method() { cat /tmp/canvas_method 2>/dev/null || echo "docker"; }
    canvas_query() {
        local query="$1"
        local method=$(_get_canvas_method)
        if [ "$method" = "docker" ]; then
            docker exec canvas-lms psql -U canvas -d canvas_development -t -A -c "$query" 2>/dev/null
        else
            psql -U canvas -d canvas_development -t -A -c "$query" 2>/dev/null
        fi
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
mkdir -p /workspace/evidence 2>/dev/null || true
cp /tmp/task_end_screenshot.png /workspace/evidence/span101_scheduler_final.png 2>/dev/null || true

# Get Course ID
COURSE_ID=$(cat /tmp/span101_course_id 2>/dev/null || echo "")
if [ -z "$COURSE_ID" ]; then
    COURSE_ID=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='span101' LIMIT 1")
fi

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Query for the Appointment Group
# We look for active groups linked to the course created after task start
echo "Searching for appointment group..."

# SQL query to get details
# We join appointment_groups and appointment_group_contexts
# We want: id, title, location, duration, limit, workflow_state, created_at
QUERY="SELECT g.id, g.title, g.location_name, g.duration_minutes, g.participants_per_appointment, g.workflow_state, EXTRACT(EPOCH FROM g.created_at)::bigint
       FROM appointment_groups g
       JOIN appointment_group_contexts c ON g.id = c.appointment_group_id
       WHERE c.context_id = $COURSE_ID 
       AND c.context_type = 'Course'
       AND g.workflow_state = 'active'
       ORDER BY g.id DESC LIMIT 1"

DATA=$(canvas_query "$QUERY")

FOUND="false"
GROUP_ID=""
TITLE=""
LOCATION=""
DURATION=""
LIMIT_PARTICIPANTS=""
STATE=""
CREATED_AT="0"

if [ -n "$DATA" ]; then
    FOUND="true"
    GROUP_ID=$(echo "$DATA" | cut -d'|' -f1)
    TITLE=$(echo "$DATA" | cut -d'|' -f2)
    LOCATION=$(echo "$DATA" | cut -d'|' -f3)
    DURATION=$(echo "$DATA" | cut -d'|' -f4)
    LIMIT_PARTICIPANTS=$(echo "$DATA" | cut -d'|' -f5)
    STATE=$(echo "$DATA" | cut -d'|' -f6)
    CREATED_AT=$(echo "$DATA" | cut -d'|' -f7)
fi

# Check slot generation (are there actual appointments created?)
# Appointment groups create 'calendar_events' or 'appointment_group_sub_contexts'
SLOTS_CREATED="false"
if [ "$FOUND" = "true" ]; then
    # Check if there are appointment slots linked to this group
    SLOT_COUNT=$(canvas_query "SELECT COUNT(*) FROM calendar_events WHERE appointment_group_id = $GROUP_ID AND workflow_state = 'active'")
    if [ "$SLOT_COUNT" -gt 0 ]; then
        SLOTS_CREATED="true"
    fi
fi

# Sanitize strings for JSON
TITLE_ESC=$(echo "$TITLE" | sed 's/"/\\"/g')
LOCATION_ESC=$(echo "$LOCATION" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/span101_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "group_found": $FOUND,
    "group": {
        "id": "$GROUP_ID",
        "title": "$TITLE_ESC",
        "location": "$LOCATION_ESC",
        "duration_minutes": "${DURATION:-0}",
        "participants_limit": "${LIMIT_PARTICIPANTS:-0}",
        "workflow_state": "$STATE",
        "created_at": ${CREATED_AT:-0}
    },
    "slots_created": $SLOTS_CREATED,
    "course_id": "$COURSE_ID"
}
EOF

# Save to public location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="