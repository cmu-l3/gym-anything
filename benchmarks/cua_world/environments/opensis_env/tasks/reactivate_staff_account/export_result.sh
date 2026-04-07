#!/bin/bash
echo "=== Exporting Reactivate Staff Account results ==="

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

TARGET_STAFF_ID=$(cat /tmp/target_staff_id.txt 2>/dev/null || echo "0")
INITIAL_STAFF_COUNT=$(cat /tmp/initial_staff_count.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check current status of the TARGET staff ID
# We want opensis_access to be 'Y'
CURRENT_ACCESS=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -s -e "SELECT opensis_access FROM staff_school_info WHERE staff_id=$TARGET_STAFF_ID LIMIT 1")

# 2. Check for duplicate records (Anti-Gaming)
# If agent created a NEW James Helper instead of fixing the old one, count will increase
CURRENT_STAFF_COUNT=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -s -e "SELECT COUNT(*) FROM staff WHERE first_name='James' AND last_name='Helper'")

# 3. Get profile info to ensure role is preserved
CURRENT_PROFILE=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -s -e "SELECT opensis_profile FROM staff_school_info WHERE staff_id=$TARGET_STAFF_ID LIMIT 1")

# 4. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON Result
# Using python for safe JSON creation
python3 -c "
import json
import os

result = {
    'target_staff_id': $TARGET_STAFF_ID,
    'initial_access': 'N',
    'current_access': '$CURRENT_ACCESS',
    'initial_count': int('$INITIAL_STAFF_COUNT'),
    'current_count': int('$CURRENT_STAFF_COUNT'),
    'current_profile': '$CURRENT_PROFILE',
    'task_start': $TASK_START_TIME,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions so the host can read it (if using shared mounts) or for copy_from_env
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json