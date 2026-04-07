#!/bin/bash
set -e
echo "=== Exporting Mark Student Retention Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Result
# We need to capture the student's ID and their rolling/retention status.
# Schema handling: OpenSIS versions vary. We'll dump the specific record to JSON.
# We check common fields for retention info: rolling_option, next_grade_id, retention
echo "Querying database..."

# Helper to run query and get JSON-like output structure
QUERY="SELECT student_id, first_name, last_name, grade_level, rolling_option, next_grade_id, last_updated 
       FROM students 
       WHERE first_name='Robert' AND last_name='Failson' 
       LIMIT 1"

# Execute query using mysql directly
# We use -E (vertical) or construct JSON manually to be safe
RESULT_RAW=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "$QUERY" 2>/dev/null || echo "")

# Parse the tab-separated result
# Expected cols: id, first, last, grade, rolling_option, next_grade, last_updated
read -r S_ID S_FIRST S_LAST S_GRADE S_ROLLING S_NEXT S_UPDATED <<< "$RESULT_RAW"

# Check if student found
if [ -n "$S_ID" ]; then
    STUDENT_FOUND="true"
else
    STUDENT_FOUND="false"
fi

# 3. Check for enrollment table data (some versions split this)
QUERY_ENROLL="SELECT rolling_option FROM student_enrollment WHERE student_id='$S_ID' ORDER BY enrollment_id DESC LIMIT 1"
ENROLL_ROLLING=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "$QUERY_ENROLL" 2>/dev/null || echo "")

# If the main student table rolling option is empty, use the enrollment table one
FINAL_ROLLING="$S_ROLLING"
if [ -z "$FINAL_ROLLING" ] && [ -n "$ENROLL_ROLLING" ]; then
    FINAL_ROLLING="$ENROLL_ROLLING"
fi

# 4. Check App Status
APP_RUNNING="false"
if pgrep -f "chrome" > /dev/null || pgrep -f "chromium" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "student_found": $STUDENT_FOUND,
    "student_data": {
        "id": "${S_ID:-0}",
        "first_name": "${S_FIRST:-}",
        "last_name": "${S_LAST:-}",
        "grade": "${S_GRADE:-}",
        "rolling_option": "${FINAL_ROLLING:-}",
        "next_grade_id": "${S_NEXT:-}",
        "last_updated": "${S_UPDATED:-}"
    },
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="