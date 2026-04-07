#!/bin/bash
# Export script for Create Feedback Evaluation task

echo "=== Exporting Create Feedback Evaluation Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

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
    # Query with headers for JSON construction if needed
    moodle_query_json() {
        local query="$1"
        local method=$(_get_mariadb_method)
        # Use python to convert mysql output to json if complex, but simple retrieval is safer here
        # We will iterate in bash for safety
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

# Retrieve stored course ID and baseline
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_feedback_count 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Find the specific feedback activity created
# Look for 'End of Semester Course Evaluation' (case-insensitive)
FEEDBACK_DATA=$(moodle_query "SELECT id, name, anonymous, multiple_submit, timemodified FROM mdl_feedback WHERE course=$COURSE_ID AND LOWER(name) LIKE '%end of semester course evaluation%' ORDER BY id DESC LIMIT 1")

FEEDBACK_FOUND="false"
FEEDBACK_ID=""
FEEDBACK_NAME=""
IS_ANONYMOUS="0"
MULTIPLE_SUBMIT="0"
TIMEMODIFIED="0"
ITEMS_JSON="[]"

if [ -n "$FEEDBACK_DATA" ]; then
    FEEDBACK_FOUND="true"
    FEEDBACK_ID=$(echo "$FEEDBACK_DATA" | cut -f1 | tr -d '[:space:]')
    FEEDBACK_NAME=$(echo "$FEEDBACK_DATA" | cut -f2)
    IS_ANONYMOUS=$(echo "$FEEDBACK_DATA" | cut -f3 | tr -d '[:space:]')
    MULTIPLE_SUBMIT=$(echo "$FEEDBACK_DATA" | cut -f4 | tr -d '[:space:]')
    TIMEMODIFIED=$(echo "$FEEDBACK_DATA" | cut -f5 | tr -d '[:space:]')

    echo "Feedback found: ID=$FEEDBACK_ID, Name='$FEEDBACK_NAME', Anon=$IS_ANONYMOUS"

    # Fetch items (questions) for this feedback
    # typ: multichoice, numeric, textfield, textarea, etc.
    # name: question text (usually)
    # presentation: options or ranges
    
    # We construct a JSON array of items manually to avoid complex dependencies
    ITEMS_RAW=$(moodle_query "SELECT typ, name, presentation FROM mdl_feedback_item WHERE feedback=$FEEDBACK_ID ORDER BY position")
    
    # Build JSON array string
    ITEMS_JSON="["
    FIRST=1
    while IFS=$'\t' read -r TYP NAME PRES; do
        if [ "$FIRST" -eq 0 ]; then ITEMS_JSON="$ITEMS_JSON,"; fi
        
        # Escape quotes for JSON
        NAME_ESC=$(echo "$NAME" | sed 's/"/\\"/g' | sed 's/	/ /g')
        PRES_ESC=$(echo "$PRES" | sed 's/"/\\"/g' | sed 's/	/ /g')
        TYP_ESC=$(echo "$TYP" | sed 's/"/\\"/g')
        
        ITEMS_JSON="$ITEMS_JSON {\"type\": \"$TYP_ESC\", \"name\": \"$NAME_ESC\", \"presentation\": \"$PRES_ESC\"}"
        FIRST=0
    done <<< "$ITEMS_RAW"
    ITEMS_JSON="$ITEMS_JSON]"

else
    echo "Feedback activity NOT found in HIST201"
fi

# Current count check
CURRENT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_feedback WHERE course=$COURSE_ID" | tr -d '[:space:]')

# Escape name for JSON
FEEDBACK_NAME_ESC=$(echo "$FEEDBACK_NAME" | sed 's/"/\\"/g')

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/feedback_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "feedback_found": $FEEDBACK_FOUND,
    "feedback_id": "${FEEDBACK_ID}",
    "feedback_name": "${FEEDBACK_NAME_ESC}",
    "anonymous": ${IS_ANONYMOUS:-0},
    "multiple_submit": ${MULTIPLE_SUBMIT:-0},
    "timemodified": ${TIMEMODIFIED:-0},
    "task_start_time": ${TASK_START_TIME:-0},
    "items": $ITEMS_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_feedback_result.json

echo ""
echo "Exported JSON content:"
cat /tmp/create_feedback_result.json
echo ""
echo "=== Export Complete ==="