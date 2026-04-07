#!/bin/bash
set -e
echo "=== Exporting drop_student_course results ==="

# Load IDs
PHILIP_ID=$(cat /tmp/target_student_id.txt 2>/dev/null || echo "0")
CP_ID=$(cat /tmp/target_cp_id.txt 2>/dev/null || echo "0")
COURSE_ID=$(cat /tmp/target_course_id.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DB_NAME="opensis"
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N"

# 1. Check if schedule record still exists (Target: Should be 0)
SCHEDULE_EXISTS=$($MYSQL_CMD -e "SELECT COUNT(*) FROM schedule WHERE student_id=$PHILIP_ID AND course_period_id=$CP_ID;" 2>/dev/null || echo "-1")

# 2. Check if student still exists (Safety: Should be 1)
STUDENT_EXISTS=$($MYSQL_CMD -e "SELECT COUNT(*) FROM students WHERE student_id=$PHILIP_ID;" 2>/dev/null || echo "0")

# 3. Check if course still exists (Safety: Should be 1)
COURSE_EXISTS=$($MYSQL_CMD -e "SELECT COUNT(*) FROM courses WHERE course_id=$COURSE_ID;" 2>/dev/null || echo "0")

# 4. Get current total schedule count for student
FINAL_SCHEDULE_COUNT=$($MYSQL_CMD -e "SELECT COUNT(*) FROM schedule WHERE student_id=$PHILIP_ID;" 2>/dev/null || echo "0")
INITIAL_SCHEDULE_COUNT=$(cat /tmp/initial_schedule_count.txt 2>/dev/null || echo "0")

# 5. Check if any relevant tables were modified after task start
# We check information_schema for table update times
TABLE_MODIFIED=$($MYSQL_CMD -e "
SELECT COUNT(*) FROM information_schema.tables 
WHERE table_schema='$DB_NAME' 
AND table_name='schedule' 
AND update_time > FROM_UNIXTIME($TASK_START);" 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "schedule_record_count": $SCHEDULE_EXISTS,
    "student_record_exists": $STUDENT_EXISTS,
    "course_record_exists": $COURSE_EXISTS,
    "initial_total_schedule_count": $INITIAL_SCHEDULE_COUNT,
    "final_total_schedule_count": $FINAL_SCHEDULE_COUNT,
    "db_table_modified_after_start": $TABLE_MODIFIED,
    "target_ids": {
        "student": "$PHILIP_ID",
        "course": "$COURSE_ID",
        "section": "$CP_ID"
    },
    "timestamp": "$(date +%s)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json