#!/bin/bash
set -e

echo "=== Exporting cancel_course_enrollments results ==="

# DB Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Helper query function
run_query() {
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "$1"
}

# 1. Get IDs
ART_COURSE_ID=$(run_query "SELECT course_id FROM courses WHERE course_code='ART-303' LIMIT 1")
MATH_COURSE_ID=$(run_query "SELECT course_id FROM courses WHERE course_code='MATH-101' LIMIT 1")

# If course was deleted, ART_COURSE_ID will be empty
if [ -z "$ART_COURSE_ID" ]; then
    ART_EXISTS="false"
    ART_CP_ID="0"
else
    ART_EXISTS="true"
    ART_CP_ID=$(run_query "SELECT course_period_id FROM course_periods WHERE course_id=$ART_COURSE_ID LIMIT 1")
    # If section was deleted
    if [ -z "$ART_CP_ID" ]; then
        SECTION_EXISTS="false"
        ART_CP_ID="0"
    else
        SECTION_EXISTS="true"
    fi
fi

if [ -z "$MATH_COURSE_ID" ]; then
    MATH_CP_ID="0"
else
    MATH_CP_ID=$(run_query "SELECT course_period_id FROM course_periods WHERE course_id=$MATH_COURSE_ID LIMIT 1")
fi

# 2. Check Enrollments (The Core Metric)
if [ "$ART_CP_ID" != "0" ]; then
    ART_ENROLLMENT_COUNT=$(run_query "SELECT COUNT(*) FROM schedule WHERE course_period_id=$ART_CP_ID")
else
    ART_ENROLLMENT_COUNT=0
fi

if [ -n "$MATH_CP_ID" ] && [ "$MATH_CP_ID" != "0" ]; then
    CONTROL_ENROLLMENT_COUNT=$(run_query "SELECT COUNT(*) FROM schedule WHERE course_period_id=$MATH_CP_ID")
else
    CONTROL_ENROLLMENT_COUNT=0
fi

# 3. Check if students are still active (not deleted or withdrawn from school)
# We check the 5 PotteryUsers
STUDENT_ACTIVE_COUNT=$(run_query "SELECT COUNT(*) FROM students WHERE first_name LIKE 'PotteryUser%' AND is_active='Y'")

# 4. Anti-gaming: Check modification times or logs if possible
# (Using task start time vs DB activity is hard with just mysql, relying on state)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 5. Take Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "art_course_exists": $ART_EXISTS,
    "section_exists": $SECTION_EXISTS,
    "art_enrollment_count": ${ART_ENROLLMENT_COUNT:-0},
    "control_enrollment_count": ${CONTROL_ENROLLMENT_COUNT:-0},
    "active_student_count": ${STUDENT_ACTIVE_COUNT:-0},
    "task_start_timestamp": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json