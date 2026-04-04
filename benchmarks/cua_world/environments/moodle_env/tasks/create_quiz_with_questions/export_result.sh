#!/bin/bash
# Export script for Create Quiz with Questions task

echo "=== Exporting Create Quiz with Questions Result ==="

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

# Get BIO101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')

# Get baseline
INITIAL_QUIZ_COUNT=$(cat /tmp/initial_quiz_count 2>/dev/null || echo "0")

# Get current quiz count
CURRENT_QUIZ_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_QUIZ_COUNT=${CURRENT_QUIZ_COUNT:-0}

echo "Quiz count: initial=$INITIAL_QUIZ_COUNT, current=$CURRENT_QUIZ_COUNT"

# Look for the target quiz (case-insensitive match on key terms)
QUIZ_DATA=$(moodle_query "SELECT id, name, timelimit, attempts FROM mdl_quiz WHERE course=$COURSE_ID AND LOWER(name) LIKE '%midterm%' AND LOWER(name) LIKE '%cell biology%' ORDER BY id DESC LIMIT 1")

QUIZ_FOUND="false"
QUIZ_ID=""
QUIZ_NAME=""
QUIZ_TIMELIMIT="0"
QUIZ_ATTEMPTS="0"
QUESTION_COUNT="0"

if [ -n "$QUIZ_DATA" ]; then
    QUIZ_FOUND="true"
    QUIZ_ID=$(echo "$QUIZ_DATA" | cut -f1 | tr -d '[:space:]')
    QUIZ_NAME=$(echo "$QUIZ_DATA" | cut -f2)
    QUIZ_TIMELIMIT=$(echo "$QUIZ_DATA" | cut -f3 | tr -d '[:space:]')
    QUIZ_ATTEMPTS=$(echo "$QUIZ_DATA" | cut -f4 | tr -d '[:space:]')

    # Count question slots in the quiz
    QUESTION_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_slots WHERE quizid=$QUIZ_ID" | tr -d '[:space:]')

    echo "Quiz found: ID=$QUIZ_ID, Name='$QUIZ_NAME', TimeLimit=$QUIZ_TIMELIMIT, Attempts=$QUIZ_ATTEMPTS"
    echo "Question slot count: $QUESTION_COUNT"
else
    echo "Target quiz NOT found in BIO101"
fi

# Verify quiz is in the correct course (for wrong-target detection)
QUIZ_COURSE_ID=""
if [ -n "$QUIZ_ID" ]; then
    QUIZ_COURSE_ID=$(moodle_query "SELECT course FROM mdl_quiz WHERE id=$QUIZ_ID" | tr -d '[:space:]')
fi

# Escape for JSON
QUIZ_NAME_ESC=$(echo "$QUIZ_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/create_quiz_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_quiz_count": ${INITIAL_QUIZ_COUNT:-0},
    "current_quiz_count": ${CURRENT_QUIZ_COUNT:-0},
    "quiz_found": $QUIZ_FOUND,
    "quiz_id": "$QUIZ_ID",
    "quiz_name": "$QUIZ_NAME_ESC",
    "quiz_course_id": "$QUIZ_COURSE_ID",
    "quiz_timelimit": ${QUIZ_TIMELIMIT:-0},
    "quiz_attempts": ${QUIZ_ATTEMPTS:-0},
    "question_count": ${QUESTION_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_quiz_with_questions_result.json

echo ""
cat /tmp/create_quiz_with_questions_result.json
echo ""
echo "=== Export Complete ==="
