#!/bin/bash
# Export script for Configure Course Completion Logic task

echo "=== Exporting Course Completion Logic Result ==="

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

# Get SAFE101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='SAFE101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: Course SAFE101 not found"
    COURSE_ID=0
fi

echo "Checking Course ID: $COURSE_ID"

# 1. Check Quiz 'Grade to Pass'
# Get Quiz module ID and Grade Item info
QUIZ_NAME="Safety Certification Exam"
QUIZ_DATA=$(moodle_query "SELECT id FROM mdl_quiz WHERE course=$COURSE_ID AND name='$QUIZ_NAME'")
QUIZ_INSTANCE_ID=$(echo "$QUIZ_DATA" | tr -d '[:space:]')

QUIZ_GRADEPASS="0"
if [ -n "$QUIZ_INSTANCE_ID" ]; then
    # Get grade_item for this quiz
    QUIZ_GRADEPASS=$(moodle_query "SELECT gradepass FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemtype='mod' AND itemmodule='quiz' AND iteminstance=$QUIZ_INSTANCE_ID")
fi
QUIZ_GRADEPASS=${QUIZ_GRADEPASS:-0}

# 2. Check Quiz Activity Completion Settings
# Get Course Module (CM) ID for the quiz
QUIZ_CM_DATA=$(moodle_query "SELECT id, completion, completionview, completionpassgrade FROM mdl_course_modules WHERE course=$COURSE_ID AND instance=$QUIZ_INSTANCE_ID AND module=(SELECT id FROM mdl_modules WHERE name='quiz')")
QUIZ_CM_ID=$(echo "$QUIZ_CM_DATA" | cut -f1)
QUIZ_COMPLETION=$(echo "$QUIZ_CM_DATA" | cut -f2)
QUIZ_REQ_VIEW=$(echo "$QUIZ_CM_DATA" | cut -f3)
QUIZ_REQ_PASSGRADE=$(echo "$QUIZ_CM_DATA" | cut -f4)

# 3. Check Handbook Activity Completion Settings
HANDBOOK_NAME="Employee Handbook"
PAGE_INSTANCE_ID=$(moodle_query "SELECT id FROM mdl_page WHERE course=$COURSE_ID AND name='$HANDBOOK_NAME'" | tr -d '[:space:]')

HANDBOOK_CM_DATA=$(moodle_query "SELECT id, completion, completionview FROM mdl_course_modules WHERE course=$COURSE_ID AND instance=$PAGE_INSTANCE_ID AND module=(SELECT id FROM mdl_modules WHERE name='page')")
HANDBOOK_CM_ID=$(echo "$HANDBOOK_CM_DATA" | cut -f1)
HANDBOOK_COMPLETION=$(echo "$HANDBOOK_CM_DATA" | cut -f2)
HANDBOOK_REQ_VIEW=$(echo "$HANDBOOK_CM_DATA" | cut -f3)

# 4. Check Course Completion Criteria (Activity Dependencies)
# Check if criteria exists for both CM IDs
CRITERIA_QUIZ_EXISTS="false"
if [ -n "$QUIZ_CM_ID" ]; then
    COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_course_completion_criteria WHERE course=$COURSE_ID AND criteriatype=4 AND moduleinstance=$QUIZ_CM_ID")
    if [ "$COUNT" -gt 0 ]; then CRITERIA_QUIZ_EXISTS="true"; fi
fi

CRITERIA_HANDBOOK_EXISTS="false"
if [ -n "$HANDBOOK_CM_ID" ]; then
    COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_course_completion_criteria WHERE course=$COURSE_ID AND criteriatype=4 AND moduleinstance=$HANDBOOK_CM_ID")
    if [ "$COUNT" -gt 0 ]; then CRITERIA_HANDBOOK_EXISTS="true"; fi
fi

# 5. Check Aggregation Method (ALL vs ANY) for Activity Completion (Type 4)
# method: 1 = ALL, 2 = ANY
AGGR_METHOD=$(moodle_query "SELECT method FROM mdl_course_completion_aggr_meth WHERE course=$COURSE_ID AND criteriatype=4" | tr -d '[:space:]')
# If no specific record, check if there is a general aggregation record (criteriatype IS NULL) that might apply, but Moodle usually stores it per type if configured.
# If return is empty, it might default.

echo "Quiz Gradepass: $QUIZ_GRADEPASS"
echo "Quiz Completion: Mode=$QUIZ_COMPLETION, PassGrade=$QUIZ_REQ_PASSGRADE"
echo "Handbook Completion: Mode=$HANDBOOK_COMPLETION, View=$HANDBOOK_REQ_VIEW"
echo "Criteria Exists: Quiz=$CRITERIA_QUIZ_EXISTS, Handbook=$CRITERIA_HANDBOOK_EXISTS"
echo "Aggregation Method: $AGGR_METHOD"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/completion_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "quiz_gradepass": ${QUIZ_GRADEPASS:-0},
    "quiz_cm_id": ${QUIZ_CM_ID:-0},
    "quiz_completion_mode": ${QUIZ_COMPLETION:-0},
    "quiz_req_passgrade": ${QUIZ_REQ_PASSGRADE:-0},
    "handbook_cm_id": ${HANDBOOK_CM_ID:-0},
    "handbook_completion_mode": ${HANDBOOK_COMPLETION:-0},
    "handbook_req_view": ${HANDBOOK_REQ_VIEW:-0},
    "criteria_quiz_exists": $CRITERIA_QUIZ_EXISTS,
    "criteria_handbook_exists": $CRITERIA_HANDBOOK_EXISTS,
    "aggregation_method": ${AGGR_METHOD:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/course_completion_result.json

echo ""
cat /tmp/course_completion_result.json
echo ""
echo "=== Export Complete ==="