#!/bin/bash
# Export script for Enroll Student task

echo "=== Exporting Enroll Student Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read stored values
USER_ID=$(cat /tmp/target_user_id 2>/dev/null || echo "0")
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_ENROLLMENT=$(cat /tmp/initial_enrollment_count 2>/dev/null || echo "0")
WAS_ALREADY_ENROLLED=$(cat /tmp/was_already_enrolled 2>/dev/null || echo "false")

# Get current enrollment count
CURRENT_ENROLLMENT="0"
if [ "$COURSE_ID" != "0" ]; then
    CURRENT_ENROLLMENT=$(get_enrollment_count "$COURSE_ID" 2>/dev/null || echo "0")
fi

echo "Enrollment count: initial=$INITIAL_ENROLLMENT, current=$CURRENT_ENROLLMENT"

# Check if the target user is now enrolled
IS_ENROLLED="false"
ENROLLMENT_ROLE=""
if [ "$USER_ID" != "0" ] && [ "$COURSE_ID" != "0" ]; then
    if is_user_enrolled "$USER_ID" "$COURSE_ID"; then
        IS_ENROLLED="true"
        # Get the role
        ENROLLMENT_ROLE=$(moodle_query "
            SELECT r.shortname
            FROM mdl_role_assignments ra
            JOIN mdl_role r ON ra.roleid = r.id
            JOIN mdl_context ctx ON ra.contextid = ctx.id
            WHERE ra.userid = $USER_ID
            AND ctx.contextlevel = 50
            AND ctx.instanceid = $COURSE_ID
            ORDER BY ra.id DESC LIMIT 1
        " 2>/dev/null)
        echo "User epatel IS enrolled in BIO101 with role: $ENROLLMENT_ROLE"
    else
        echo "User epatel is NOT enrolled in BIO101"
    fi
fi

# Debug: Show current enrollments for the course
echo ""
echo "=== DEBUG: Current enrollments in BIO101 ==="
moodle_query_headers "
    SELECT u.id, u.username, u.firstname, u.lastname, r.shortname as role
    FROM mdl_user_enrolments ue
    JOIN mdl_enrol e ON ue.enrolid = e.id
    JOIN mdl_user u ON ue.userid = u.id
    LEFT JOIN mdl_role_assignments ra ON ra.userid = u.id
    LEFT JOIN mdl_role r ON ra.roleid = r.id
    LEFT JOIN mdl_context ctx ON ra.contextid = ctx.id AND ctx.contextlevel = 50 AND ctx.instanceid = e.courseid
    WHERE e.courseid = $COURSE_ID AND ue.status = 0
    ORDER BY u.lastname
" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Create JSON result
TEMP_JSON=$(mktemp /tmp/enroll_student_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "user_id": $USER_ID,
    "course_id": $COURSE_ID,
    "initial_enrollment_count": ${INITIAL_ENROLLMENT:-0},
    "current_enrollment_count": ${CURRENT_ENROLLMENT:-0},
    "was_already_enrolled": $WAS_ALREADY_ENROLLED,
    "is_enrolled": $IS_ENROLLED,
    "enrollment_role": "$(echo "$ENROLLMENT_ROLE" | sed 's/"/\\"/g')",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/enroll_student_result.json

echo ""
cat /tmp/enroll_student_result.json
echo ""
echo "=== Export Complete ==="
