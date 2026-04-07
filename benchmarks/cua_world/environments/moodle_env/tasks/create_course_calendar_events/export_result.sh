#!/bin/bash
# Export script for Create Course Calendar Events task

echo "=== Exporting Create Course Calendar Events Result ==="

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

# Read stored IDs and counts
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_EVENT_COUNT=$(cat /tmp/initial_event_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get current event count
CURRENT_EVENT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_event WHERE courseid=$COURSE_ID" | tr -d '[:space:]')
CURRENT_EVENT_COUNT=${CURRENT_EVENT_COUNT:-0}

echo "Event count: initial=$INITIAL_EVENT_COUNT, current=$CURRENT_EVENT_COUNT"

# Retrieve all events for this course created or modified after task start
# We query more broadly (just by course) and let Python filter, to catch edge cases
# Select columns: id, name, description, timestart, timeduration, eventtype, timemodified
# Using a separator unlikely to be in text (e.g., |#|) is tricky in bash/mysql, 
# so we'll use JSON output directly from python or careful CSV construction.
# Here we'll construct a simple JSON array of objects using a loop.

# Get IDs of relevant events (limit 10 to be safe)
EVENT_IDS=$(moodle_query "SELECT id FROM mdl_event WHERE courseid=$COURSE_ID ORDER BY id DESC LIMIT 10")

EVENTS_JSON="["
FIRST=true

for EID in $EVENT_IDS; do
    if [ "$FIRST" = true ]; then FIRST=false; else EVENTS_JSON="$EVENTS_JSON,"; fi
    
    # Extract fields safely
    # Note: Description might contain newlines/quotes, so we select other fields cleanly
    DATA=$(moodle_query "SELECT name, timestart, timeduration, eventtype, timemodified FROM mdl_event WHERE id=$EID")
    
    # Parse tab-separated
    NAME=$(echo "$DATA" | cut -f1)
    TIMESTART=$(echo "$DATA" | cut -f2)
    TIMEDURATION=$(echo "$DATA" | cut -f3)
    EVENTTYPE=$(echo "$DATA" | cut -f4)
    TIMEMODIFIED=$(echo "$DATA" | cut -f5)
    
    # Escape name for JSON
    NAME_ESC=$(echo "$NAME" | sed 's/"/\\"/g')
    
    EVENTS_JSON="$EVENTS_JSON {
        \"id\": $EID,
        \"name\": \"$NAME_ESC\",
        \"timestart\": \"$TIMESTART\",
        \"timeduration\": \"$TIMEDURATION\",
        \"eventtype\": \"$EVENTTYPE\",
        \"timemodified\": \"$TIMEMODIFIED\"
    }"
done
EVENTS_JSON="$EVENTS_JSON ]"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/calendar_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_event_count": ${INITIAL_EVENT_COUNT:-0},
    "current_event_count": ${CURRENT_EVENT_COUNT:-0},
    "task_start_timestamp": ${TASK_START:-0},
    "events": $EVENTS_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_course_calendar_events_result.json

echo ""
echo "Exported JSON summary:"
cat /tmp/create_course_calendar_events_result.json
echo ""
echo "=== Export Complete ==="