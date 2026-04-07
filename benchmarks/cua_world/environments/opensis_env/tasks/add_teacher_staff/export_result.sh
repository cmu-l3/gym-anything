#!/bin/bash
set -e
echo "=== Exporting add_teacher_staff results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Task Execution Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_staff_count.txt 2>/dev/null || echo "0")

# 3. Query Database for Verification
# We fetch details about the staff member 'Margaret Chen' and the login 'mchen'
# Using JSON_OBJECT for structured output if available, otherwise tab-separated

echo "Querying database..."

# Query Staff Table
STAFF_DATA=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e "
SELECT staff_id, first_name, last_name, email, profile_id, current_school_id 
FROM staff 
WHERE first_name='Margaret' AND last_name='Chen' 
ORDER BY staff_id DESC LIMIT 1" 2>/dev/null || true)

# Query Login Table
LOGIN_DATA=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e "
SELECT user_id, username, profile_id 
FROM login_authentication 
WHERE username='mchen'" 2>/dev/null || true)

# Query Profile Name (to verify ID matches 'Teacher')
# Assuming profile_id comes from STAFF_DATA
STAFF_PROFILE_ID=$(echo "$STAFF_DATA" | awk '{print $5}')
PROFILE_NAME=""
if [ -n "$STAFF_PROFILE_ID" ]; then
    PROFILE_NAME=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e "
    SELECT title FROM user_profiles WHERE id='$STAFF_PROFILE_ID'" 2>/dev/null || true)
fi

# Query School Relationship
IS_LINKED_TO_SCHOOL="false"
if [ -n "$STAFF_DATA" ]; then
    STAFF_ID=$(echo "$STAFF_DATA" | awk '{print $1}')
    LINK_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "
    SELECT COUNT(*) FROM staff_school_relationship WHERE staff_id='$STAFF_ID' AND school_id=1" 2>/dev/null || echo "0")
    if [ "$LINK_COUNT" -gt "0" ]; then IS_LINKED_TO_SCHOOL="true"; fi
fi

# Get Current Total Count
CURRENT_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT COUNT(*) FROM staff" 2>/dev/null || echo "0")

# 4. Construct JSON Result
# Using python to construct valid JSON to avoid shell string escaping hell
python3 -c "
import json
import sys

try:
    staff_raw = '''$STAFF_DATA'''.strip().split('\t')
    login_raw = '''$LOGIN_DATA'''.strip().split('\t')
    
    staff_found = len(staff_raw) >= 6
    login_found = len(login_raw) >= 2
    
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'initial_count': int('$INITIAL_COUNT'),
        'current_count': int('$CURRENT_COUNT'),
        'staff_record': {
            'found': staff_found,
            'id': staff_raw[0] if staff_found else None,
            'first_name': staff_raw[1] if staff_found else None,
            'last_name': staff_raw[2] if staff_found else None,
            'email': staff_raw[3] if staff_found else None,
            'profile_id': staff_raw[4] if staff_found else None,
            'school_id': staff_raw[5] if staff_found else None,
            'profile_name': '''$PROFILE_NAME'''.strip()
        },
        'login_record': {
            'found': login_found,
            'username': login_raw[1] if login_found else None
        },
        'school_link_exists': '$IS_LINKED_TO_SCHOOL' == 'true',
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=4)
        
except Exception as e:
    print(f'Error constructing JSON: {e}', file=sys.stderr)
    # Fallback minimal JSON
    with open('/tmp/task_result.json', 'w') as f:
        f.write('{\"error\": \"Failed to parse DB output\"}')
"

# 5. Handle Permissions (so host can read it)
chmod 666 /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result.json /tmp/export_debug.json # Backup for debug

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="