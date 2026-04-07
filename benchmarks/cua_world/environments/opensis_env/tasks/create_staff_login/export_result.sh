#!/bin/bash
echo "=== Exporting Results for Create Staff Login ==="

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Get Task Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Query User Table (login_authentication)
# Check if 'sconnor' exists and get details
USER_QUERY="SELECT user_id, username, profile_id FROM login_authentication WHERE username='sconnor'"
USER_JSON=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -B -e "$USER_QUERY" | \
    jq -R -s -c 'split("\n") | .[1:] | map(select(length > 0)) | map(split("\t")) | map({"user_id": .[0], "username": .[1], "profile_id": .[2]}) | .[0] // null')

# 3. Query Staff Table
# Check Sarah Connor's record and specifically her USER_ID link
STAFF_QUERY="SELECT staff_id, first_name, last_name, USER_ID FROM staff WHERE first_name='Sarah' AND last_name='Connor'"
STAFF_JSON=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -B -e "$STAFF_QUERY" | \
    jq -R -s -c 'split("\n") | .[1:] | map(select(length > 0)) | map(split("\t")) | map({"staff_id": .[0], "first_name": .[1], "last_name": .[2], "linked_user_id": .[3]})')

# 4. Check Counts
INITIAL_STAFF_COUNT=$(cat /tmp/initial_staff_count.txt 2>/dev/null || echo "0")
FINAL_STAFF_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT COUNT(*) FROM staff;" 2>/dev/null || echo "0")

# 5. Take Final Screenshot
scrot /tmp/task_final.png 2>/dev/null || true

# 6. Construct Result JSON
# Using a python script for safer JSON construction than pure bash/jq if complex
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_staff_count': int('$INITIAL_STAFF_COUNT'),
    'final_staff_count': int('$FINAL_STAFF_COUNT'),
    'user_record': $USER_JSON if '$USER_JSON' != '' else None,
    'staff_records': $STAFF_JSON if '$STAFF_JSON' != '' else [],
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json