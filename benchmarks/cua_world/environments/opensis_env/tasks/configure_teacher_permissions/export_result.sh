#!/bin/bash
set -e
echo "=== Exporting Configure Teacher Permissions Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_perms_count.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Python script to query database and export detailed JSON result
# We use Python to handle JSON serialization reliably
python3 -c "
import json
import subprocess
import time
import sys

def run_query(query):
    cmd = ['mysql', '-u', 'opensis_user', '-popensis_password_123', 'opensis', '-N', '-B', '-e', query]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        return result
    except subprocess.CalledProcessError:
        return ''

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': int('$INITIAL_COUNT'),
    'teacher_profile_exists': False,
    'permissions': [],
    'screenshot_path': '/tmp/task_final.png'
}

# Check teacher profile existence
profile_check = run_query(\"SELECT title FROM user_profiles WHERE id=2\")
if profile_check and 'Teacher' in profile_check:
    result['teacher_profile_exists'] = True

# Get all permissions for profile 2 (Teacher)
# Schema: profile_id, modname, can_use, can_edit, can_create, can_delete
perms_raw = run_query(\"SELECT modname, can_use, can_edit FROM profile_exceptions WHERE profile_id=2\")

if perms_raw:
    for line in perms_raw.strip().split('\n'):
        if line:
            parts = line.split('\t')
            if len(parts) >= 3:
                result['permissions'].append({
                    'modname': parts[0],
                    'can_use': parts[1],
                    'can_edit': parts[2]
                })

# Save to temp file first
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/temp_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="