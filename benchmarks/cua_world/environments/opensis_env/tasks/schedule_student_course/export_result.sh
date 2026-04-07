#!/bin/bash
set -e

echo "=== Exporting schedule_student_course result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Metadata
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_schedule_count.txt 2>/dev/null || echo "0")

# 3. Query Database for Verification
# We check if Maria Garcia (9001) is enrolled in AP Biology (8001/7001)

# Get current schedule records for Maria
# Returns JSON-like structure or just raw lines
SCHEDULE_DATA=$(mysql -u opensis_user -popensis_password_123 opensis -N -e "
    SELECT s.student_id, cp.course_period_id, c.title, c.short_name, s.created_at
    FROM schedule s
    JOIN course_periods cp ON s.course_period_id = cp.course_period_id
    JOIN courses c ON cp.course_id = c.course_id
    WHERE s.student_id = 9001;
" 2>/dev/null || echo "")

# Check specifically for BIO-201
IS_ENROLLED="false"
if echo "$SCHEDULE_DATA" | grep -q "BIO-201"; then
    IS_ENROLLED="true"
fi

# Get current total count for Maria
CURRENT_COUNT=$(mysql -u opensis_user -popensis_password_123 opensis -N -e "SELECT COUNT(*) FROM schedule WHERE student_id=9001" 2>/dev/null || echo "0")

# Check for "Do Nothing" (Count unchanged)
COUNT_CHANGED="false"
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    COUNT_CHANGED="true"
fi

# Check if app is running
APP_RUNNING="false"
if pgrep -f chrome >/dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
# Using python to safely construct JSON to handle potential special chars in DB output
python3 -c "
import json
import os
import sys

try:
    result = {
        'task_start': $START_TIME,
        'initial_count': int('$INITIAL_COUNT'),
        'current_count': int('$CURRENT_COUNT'),
        'count_changed': '$COUNT_CHANGED' == 'true',
        'is_enrolled_target': '$IS_ENROLLED' == 'true',
        'db_dump': '''$SCHEDULE_DATA''',
        'app_running': '$APP_RUNNING' == 'true',
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error creating JSON: {e}', file=sys.stderr)
"

# 5. Permission fix
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json