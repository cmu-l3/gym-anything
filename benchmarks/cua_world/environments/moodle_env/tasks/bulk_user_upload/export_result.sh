#!/bin/bash
# Export script for Bulk User Upload task

echo "=== Exporting Bulk User Upload Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get User Data
echo "Querying created users..."
TARGET_USERS="'tnguyen','rkapoor','lchen','mhernandez','sproctor','jokwu','kfischer','dpatel'"

# Get details of the uploaded users
# Format: username|email|city|timecreated
USER_DATA_RAW=$(moodle_query "SELECT username, email, city, timecreated FROM mdl_user WHERE username IN ($TARGET_USERS) ORDER BY username")

# 2. Get Enrollment Data for BIO101
echo "Querying enrollments..."
# Get course ID for BIO101
COURSE_ID=$(get_course_by_shortname "BIO101" | cut -f1)

# Get list of enrolled usernames from the target list
ENROLLED_USERS_RAW=""
if [ -n "$COURSE_ID" ]; then
    ENROLLED_USERS_RAW=$(moodle_query "
        SELECT u.username 
        FROM mdl_user_enrolments ue
        JOIN mdl_enrol e ON ue.enrolid = e.id
        JOIN mdl_user u ON ue.userid = u.id
        WHERE e.courseid = $COURSE_ID 
        AND u.username IN ($TARGET_USERS)
        AND ue.status = 0
    ")
fi

# 3. Get Counts
INITIAL_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_user_count 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 4. Construct JSON
TEMP_JSON=$(mktemp /tmp/bulk_upload_result.XXXXXX.json)

# Python script to format SQL output into JSON to avoid bash escaping hell
python3 -c "
import json
import sys
import time

try:
    user_data_raw = '''$USER_DATA_RAW'''
    enrolled_users_raw = '''$ENROLLED_USERS_RAW'''
    
    users = {}
    for line in user_data_raw.strip().split('\n'):
        if not line: continue
        parts = line.split('\t')
        if len(parts) >= 4:
            users[parts[0]] = {
                'email': parts[1],
                'city': parts[2],
                'timecreated': int(parts[3])
            }
            
    enrolled = []
    for line in enrolled_users_raw.strip().split('\n'):
        if line: enrolled.append(line.strip())
        
    result = {
        'initial_user_count': int('$INITIAL_COUNT'),
        'current_user_count': int('$CURRENT_COUNT'),
        'task_start_time': int('$TASK_START_TIME'),
        'users_found': users,
        'users_enrolled_bio101': enrolled,
        'export_timestamp': time.strftime('%Y-%m-%dT%H:%M:%S')
    }
    
    print(json.dumps(result, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

safe_write_json "$TEMP_JSON" /tmp/bulk_upload_result.json

echo ""
cat /tmp/bulk_upload_result.json
echo ""
echo "=== Export Complete ==="