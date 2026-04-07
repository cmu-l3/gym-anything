#!/bin/bash
# Export script for Reset Course Data task

echo "=== Exporting Reset Course Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load Course ID
COURSE_ID=$(cat /tmp/course_id 2>/dev/null)
if [ -z "$COURSE_ID" ]; then
    # Fallback lookup
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
fi

if [ -z "$COURSE_ID" ]; then
    echo "ERROR: Course BIO101 not found!"
    cat > /tmp/task_result.json << EOF
{
    "course_exists": false,
    "fatal_error": "Course not found"
}
EOF
    exit 0
fi

# 1. Check if course content still exists (Anti-deletion check)
MODULE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_course_modules WHERE course=$COURSE_ID")
echo "Remaining Modules: $MODULE_COUNT"

# 2. Check Data Counts (Should be 0)
# Assignment Submissions
SUBMISSION_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_assign_submission s JOIN mdl_assign a ON s.assignment=a.id WHERE a.course=$COURSE_ID")

# Quiz Attempts
ATTEMPT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_attempts qa JOIN mdl_quiz q ON qa.quiz=q.id WHERE q.course=$COURSE_ID")

# Forum Posts (excluding stale data potentially, but we expect clear)
POST_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_forum_posts fp JOIN mdl_forum_discussions fd ON fp.discussion=fd.id WHERE fd.course=$COURSE_ID")

# 3. Check Enrollment
# Specifically check if jsmith is enrolled
JSMITH_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='jsmith'" | tr -d '[:space:]')
IS_JSMITH_ENROLLED="false"
if [ -n "$JSMITH_ID" ]; then
    if is_user_enrolled "$JSMITH_ID" "$COURSE_ID"; then
        IS_JSMITH_ENROLLED="true"
    fi
fi
echo "Is jsmith enrolled: $IS_JSMITH_ENROLLED"

# 4. Check Course Start Date
START_DATE=$(moodle_query "SELECT startdate FROM mdl_course WHERE id=$COURSE_ID" | tr -d '[:space:]')
echo "New Start Date Timestamp: $START_DATE"

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/reset_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": "$COURSE_ID",
    "course_exists": true,
    "module_count": ${MODULE_COUNT:-0},
    "submission_count": ${SUBMISSION_COUNT:-0},
    "attempt_count": ${ATTEMPT_COUNT:-0},
    "post_count": ${POST_COUNT:-0},
    "jsmith_enrolled": $IS_JSMITH_ENROLLED,
    "start_date": ${START_DATE:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="