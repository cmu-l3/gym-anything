#!/bin/bash
# Export script for Create Course task

echo "=== Exporting Create Course Result ==="

# Source shared utilities (with explicit bash sourcing)
. /workspace/scripts/task_utils.sh

# Fallback: Define moodle_query inline if sourcing didn't work
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() {
        cat /tmp/mariadb_method 2>/dev/null || echo "native"
    }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    moodle_query_headers() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
        fi
    }
    get_course_count() {
        moodle_query "SELECT COUNT(*) FROM mdl_course WHERE id > 1"
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
        [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
    }
    safe_write_json() {
        local temp_file="$1"
        local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"
        chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"
        echo "Result saved to $dest_path"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current course count
CURRENT_COUNT=$(get_course_count 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_course_count 2>/dev/null || echo "0")

echo "Course count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent courses
echo ""
echo "=== DEBUG: Most recent courses in database ==="
moodle_query_headers "SELECT id, fullname, shortname, category FROM mdl_course WHERE id > 1 ORDER BY id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check for the target course - EXACT match only, no fallbacks
# Search by exact shortname (case-insensitive)
echo "Searching for course with shortname 'DS101' (exact match, case-insensitive)..."
COURSE_DATA=$(moodle_query "SELECT id, fullname, shortname, category FROM mdl_course WHERE LOWER(TRIM(shortname))='ds101' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# NO FALLBACKS - only exact shortname match allowed
# The verifier requires exact matching - partial matches would give false positives
if [ -z "$COURSE_DATA" ]; then
    echo "Course with shortname 'DS101' NOT found in database."
    echo "No fallback queries - only exact shortname match accepted."
fi

# Parse course data
COURSE_FOUND="false"
COURSE_ID=""
COURSE_FULLNAME=""
COURSE_SHORTNAME=""
COURSE_CATEGORY_ID=""
COURSE_CATEGORY_NAME=""

if [ -n "$COURSE_DATA" ]; then
    COURSE_FOUND="true"
    COURSE_ID=$(echo "$COURSE_DATA" | cut -f1)
    COURSE_FULLNAME=$(echo "$COURSE_DATA" | cut -f2)
    COURSE_SHORTNAME=$(echo "$COURSE_DATA" | cut -f3)
    COURSE_CATEGORY_ID=$(echo "$COURSE_DATA" | cut -f4)

    # Get category name
    COURSE_CATEGORY_NAME=$(moodle_query "SELECT name FROM mdl_course_categories WHERE id=$COURSE_CATEGORY_ID" 2>/dev/null)

    echo "Course found: ID=$COURSE_ID, Name='$COURSE_FULLNAME', Short='$COURSE_SHORTNAME', Category='$COURSE_CATEGORY_NAME' (id=$COURSE_CATEGORY_ID)"
else
    echo "Course 'Data Science 101' NOT found in database"
fi

# Escape special characters for JSON
COURSE_FULLNAME_ESC=$(echo "$COURSE_FULLNAME" | sed 's/"/\\"/g')
COURSE_SHORTNAME_ESC=$(echo "$COURSE_SHORTNAME" | sed 's/"/\\"/g')
COURSE_CATEGORY_NAME_ESC=$(echo "$COURSE_CATEGORY_NAME" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/create_course_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_course_count": ${INITIAL_COUNT:-0},
    "current_course_count": ${CURRENT_COUNT:-0},
    "course_found": $COURSE_FOUND,
    "course": {
        "id": "$COURSE_ID",
        "fullname": "$COURSE_FULLNAME_ESC",
        "shortname": "$COURSE_SHORTNAME_ESC",
        "category_id": "$COURSE_CATEGORY_ID",
        "category_name": "$COURSE_CATEGORY_NAME_ESC"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_course_result.json

echo ""
cat /tmp/create_course_result.json
echo ""
echo "=== Export Complete ==="
