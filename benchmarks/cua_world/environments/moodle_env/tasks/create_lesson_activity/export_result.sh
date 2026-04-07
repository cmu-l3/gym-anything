#!/bin/bash
# Export script for Create Lesson Activity task

echo "=== Exporting Create Lesson Activity Result ==="

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

# Get stored values
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_LESSON_COUNT=$(cat /tmp/initial_lesson_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get current lesson count
CURRENT_LESSON_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_lesson WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_LESSON_COUNT=${CURRENT_LESSON_COUNT:-0}

echo "Lesson count: initial=$INITIAL_LESSON_COUNT, current=$CURRENT_LESSON_COUNT"

# Find the specific lesson (fuzzy match on name)
# We look for the most recently modified one matching the pattern
LESSON_DATA=$(moodle_query "SELECT id, name, timemodified FROM mdl_lesson WHERE course=$COURSE_ID AND name LIKE '%Cell Biology%Interactive%Lesson%' ORDER BY timemodified DESC LIMIT 1")

LESSON_FOUND="false"
LESSON_ID=""
LESSON_NAME=""
LESSON_TIMEMODIFIED="0"
CONTENT_PAGE_COUNT="0"
QUESTION_PAGE_COUNT="0"
QUESTION_HAS_ANSWERS="false"
HAS_CORRECT_ANSWER="false"
ANSWER_COUNT="0"

if [ -n "$LESSON_DATA" ]; then
    LESSON_FOUND="true"
    LESSON_ID=$(echo "$LESSON_DATA" | cut -f1 | tr -d '[:space:]')
    LESSON_NAME=$(echo "$LESSON_DATA" | cut -f2)
    LESSON_TIMEMODIFIED=$(echo "$LESSON_DATA" | cut -f3 | tr -d '[:space:]')

    echo "Lesson found: ID=$LESSON_ID, Name='$LESSON_NAME'"

    # Count Content Pages (qtype = 20)
    CONTENT_PAGE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_lesson_pages WHERE lessonid=$LESSON_ID AND qtype=20" | tr -d '[:space:]')
    
    # Count Question Pages (qtype IN (1, 2, 3, 5, 10)) - usually 3 is Multichoice, 2 is T/F
    QUESTION_PAGE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_lesson_pages WHERE lessonid=$LESSON_ID AND qtype IN (1, 2, 3, 5, 10)" | tr -d '[:space:]')

    # Analyze the question page(s)
    # Get ID of the first question page found
    QUESTION_PAGE_ID=$(moodle_query "SELECT id FROM mdl_lesson_pages WHERE lessonid=$LESSON_ID AND qtype IN (1, 2, 3, 5, 10) LIMIT 1" | tr -d '[:space:]')
    
    if [ -n "$QUESTION_PAGE_ID" ]; then
        # Count answers for this question
        ANSWER_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_lesson_answers WHERE pageid=$QUESTION_PAGE_ID" | tr -d '[:space:]')
        
        # Check if there is at least one correct answer (score > 0)
        CORRECT_ANSWERS=$(moodle_query "SELECT COUNT(*) FROM mdl_lesson_answers WHERE pageid=$QUESTION_PAGE_ID AND score > 0" | tr -d '[:space:]')
        
        if [ "$ANSWER_COUNT" -gt 0 ]; then
            QUESTION_HAS_ANSWERS="true"
        fi
        
        if [ "$CORRECT_ANSWERS" -gt 0 ]; then
            HAS_CORRECT_ANSWER="true"
        fi
        
        echo "Question Page ID: $QUESTION_PAGE_ID"
        echo "Answers: $ANSWER_COUNT"
        echo "Correct Answers: $CORRECT_ANSWERS"
    fi
else
    echo "Target lesson NOT found in BIO101"
fi

# Determine if created during task
CREATED_DURING_TASK="false"
if [ "$LESSON_TIMEMODIFIED" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Escape for JSON
LESSON_NAME_ESC=$(echo "$LESSON_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/create_lesson_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_lesson_count": ${INITIAL_LESSON_COUNT:-0},
    "current_lesson_count": ${CURRENT_LESSON_COUNT:-0},
    "lesson_found": $LESSON_FOUND,
    "lesson_id": "$LESSON_ID",
    "lesson_name": "$LESSON_NAME_ESC",
    "lesson_timemodified": ${LESSON_TIMEMODIFIED:-0},
    "created_during_task": $CREATED_DURING_TASK,
    "content_page_count": ${CONTENT_PAGE_COUNT:-0},
    "question_page_count": ${QUESTION_PAGE_COUNT:-0},
    "question_has_answers": $QUESTION_HAS_ANSWERS,
    "answer_count": ${ANSWER_COUNT:-0},
    "has_correct_answer": $HAS_CORRECT_ANSWER,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_lesson_result.json

echo ""
cat /tmp/create_lesson_result.json
echo ""
echo "=== Export Complete ==="