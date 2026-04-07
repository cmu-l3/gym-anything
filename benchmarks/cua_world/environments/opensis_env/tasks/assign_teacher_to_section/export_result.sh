#!/bin/bash
echo "=== Exporting assign_teacher result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_TEACHER=$(cat /tmp/initial_teacher_id.txt 2>/dev/null || echo "NULL")

# 3. Query Database for Final State
# We want to see who is assigned to course_period_id 202 (Chemistry 101, Period 2)
# We fetch teacher_id and join with staff table to get the name for verification
DB_RESULT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e "
    SELECT 
        cp.course_period_id,
        cp.teacher_id,
        s.first_name,
        s.last_name,
        cp.course_id
    FROM course_periods cp
    LEFT JOIN staff s ON cp.teacher_id = s.staff_id
    WHERE cp.course_period_id = 202
")

# Parse Result
# Output format: ID \t TEACHER_ID \t FIRST \t LAST \t COURSE_ID
if [ -n "$DB_RESULT" ]; then
    FINAL_TEACHER_ID=$(echo "$DB_RESULT" | cut -f2)
    FINAL_TEACHER_FIRST=$(echo "$DB_RESULT" | cut -f3)
    FINAL_TEACHER_LAST=$(echo "$DB_RESULT" | cut -f4)
else
    FINAL_TEACHER_ID="NULL"
    FINAL_TEACHER_FIRST=""
    FINAL_TEACHER_LAST=""
fi

# Handle "NULL" string from MySQL output if any
if [ "$FINAL_TEACHER_ID" == "NULL" ] || [ -z "$FINAL_TEACHER_ID" ]; then
    TEACHER_ASSIGNED="false"
else
    TEACHER_ASSIGNED="true"
fi

# Check if state changed
if [ "$INITIAL_TEACHER" == "NULL" ] && [ "$TEACHER_ASSIGNED" == "true" ]; then
    STATE_CHANGED="true"
else
    STATE_CHANGED="false"
fi

# 4. Check for Browser (App Running)
if pgrep -f "chrome\|chromium" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 5. Create JSON Report
# Using python to write JSON safely handles escaping
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'initial_teacher_id': '$INITIAL_TEACHER',
    'final_teacher_id': '$FINAL_TEACHER_ID',
    'teacher_first_name': '$FINAL_TEACHER_FIRST',
    'teacher_last_name': '$FINAL_TEACHER_LAST',
    'teacher_assigned': $TEACHER_ASSIGNED,
    'state_changed': $STATE_CHANGED,
    'app_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 6. Permissions and Cleanup
chmod 666 /tmp/task_result.json
echo "Exported result to /tmp/task_result.json"
cat /tmp/task_result.json