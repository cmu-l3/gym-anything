#!/bin/bash
# Export script for Create Video Lecture Page task

echo "=== Exporting Create Video Lecture Page Result ==="

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

# Retrieve stored course ID and baseline counts
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_PAGE_COUNT=$(cat /tmp/initial_page_count 2>/dev/null || echo "0")
INITIAL_URL_COUNT=$(cat /tmp/initial_url_count 2>/dev/null || echo "0")
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get current counts
CURRENT_PAGE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_page WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_URL_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_url WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_PAGE_COUNT=${CURRENT_PAGE_COUNT:-0}
CURRENT_URL_COUNT=${CURRENT_URL_COUNT:-0}

echo "Counts in BIO101:"
echo "  Pages: $INITIAL_PAGE_COUNT -> $CURRENT_PAGE_COUNT"
echo "  URLs:  $INITIAL_URL_COUNT -> $CURRENT_URL_COUNT"

# --- Check for correct resource (mdl_page) ---
# We look for a page created after start time in this course
PAGE_DATA=$(moodle_query "SELECT id, name, content, timecreated FROM mdl_page WHERE course=$COURSE_ID AND timecreated >= $START_TIME ORDER BY id DESC LIMIT 1")

PAGE_FOUND="false"
PAGE_ID=""
PAGE_NAME=""
PAGE_CONTENT=""
PAGE_TIMECREATED=""

if [ -n "$PAGE_DATA" ]; then
    PAGE_FOUND="true"
    # Parse tab-separated output
    PAGE_ID=$(echo "$PAGE_DATA" | cut -f1 | tr -d '[:space:]')
    PAGE_NAME=$(echo "$PAGE_DATA" | cut -f2)
    PAGE_CONTENT=$(echo "$PAGE_DATA" | cut -f3)
    PAGE_TIMECREATED=$(echo "$PAGE_DATA" | cut -f4 | tr -d '[:space:]')
    
    echo "New Page found: ID=$PAGE_ID, Name='$PAGE_NAME'"
else
    echo "No new Page resource found in BIO101."
fi

# --- Check for incorrect resource (mdl_url) ---
# To provide feedback if they made a URL instead
URL_DATA=$(moodle_query "SELECT id, name FROM mdl_url WHERE course=$COURSE_ID AND timecreated >= $START_TIME LIMIT 1")
WRONG_RESOURCE_TYPE="false"
if [ -n "$URL_DATA" ]; then
    WRONG_RESOURCE_TYPE="true"
    echo "Detected new URL resource (wrong type)."
fi

# Escape content for JSON (handled carefully to preserve structure)
# We use python to dump to json safely to avoid bash escaping hell with HTML content
python3 -c "
import json
import sys

data = {
    'course_id': $COURSE_ID,
    'initial_page_count': $INITIAL_PAGE_COUNT,
    'current_page_count': $CURRENT_PAGE_COUNT,
    'page_found': $PAGE_FOUND,
    'page_id': '$PAGE_ID',
    'page_name': sys.argv[1],
    'page_content': sys.argv[2],
    'wrong_resource_type': $WRONG_RESOURCE_TYPE,
    'export_timestamp': '$(date -Iseconds)'
}
print(json.dumps(data))
" "$PAGE_NAME" "$PAGE_CONTENT" > /tmp/create_video_result.json_temp

safe_write_json "/tmp/create_video_result.json_temp" "/tmp/create_video_result.json"

echo ""
# Don't cat the result if content is huge, just confirm
echo "Result saved to /tmp/create_video_result.json"
echo "=== Export Complete ==="