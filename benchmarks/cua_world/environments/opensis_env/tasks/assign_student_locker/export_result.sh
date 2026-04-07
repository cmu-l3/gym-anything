#!/bin/bash
set -e

echo "=== Exporting assign_student_locker results ==="

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query the database for the student's locker number
# We return JSON-formatted data directly or raw text to be parsed
echo "Querying database for Kenny McCormick..."

QUERY_RESULT=$(mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "
    SELECT first_name, last_name, locker_number 
    FROM students 
    WHERE first_name='Kenny' AND last_name='McCormick'
    LIMIT 1;
")

# Parse the result (Tab separated by default with -N)
# Example output: Kenny  McCormick  555
read -r FNAME LNAME LOCKER_VAL <<< "$QUERY_RESULT"

# Check if student was found
if [ -z "$FNAME" ]; then
    STUDENT_FOUND="false"
    LOCKER_VAL=""
else
    STUDENT_FOUND="true"
fi

# 3. Create JSON result file
# We use python to ensure valid JSON formatting to avoid shell quoting hell
python3 -c "
import json
import os

result = {
    'student_found': $STUDENT_FOUND,
    'first_name': '$FNAME',
    'last_name': '$LNAME',
    'locker_value': '$LOCKER_VAL',
    'screenshot_path': '/tmp/task_final.png',
    'task_start_time': $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 4. Safe copy to locations accessible by copy_from_env if needed (though /tmp is usually fine)
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json