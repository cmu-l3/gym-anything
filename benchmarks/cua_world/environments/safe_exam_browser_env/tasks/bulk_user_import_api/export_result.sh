#!/bin/bash
set -e
echo "=== Exporting bulk_user_import_api results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

# Extract database records for the expected users
python3 << PYEOF
import json
import time
import subprocess
import os

def db_query(query):
    try:
        result = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=30
        )
        return result.stdout.strip()
    except Exception as e:
        return ""

expected_usernames = ['asmith01', 'bjohnson02', 'cwilliams03', 'dbrown04', 'edavis05']
db_users = {}

for un in expected_usernames:
    # Query specific fields from SEB Server's user table
    # Fields typically are: id, username, name, surname, email, active
    raw = db_query(f"SELECT username, name, surname, email, active FROM user WHERE username='{un}';")
    if raw:
        parts = raw.split('\t')
        if len(parts) >= 5:
            db_users[un] = {
                "username": parts[0],
                "name": parts[1],
                "surname": parts[2],
                "email": parts[3],
                "active": parts[4] == '1'
            }

# Also verify the super-admin still exists (preventing destructive scripting)
admin_exists = db_query("SELECT COUNT(*) FROM user WHERE username='super-admin';")
admin_exists = int(admin_exists) > 0 if admin_exists else False

current_user_count = int(db_query("SELECT COUNT(*) FROM user;") or "0")

# Find any python scripts created or modified during the task duration in home dir
find_cmd = f"find /home/ga -name '*.py' -type f -newermt '@{TASK_START}' 2>/dev/null"
scripts_found = subprocess.run(find_cmd, shell=True, capture_output=True, text=True).stdout.strip().split('\n')
scripts_found = [s for s in scripts_found if s]

result = {
    "task_start_time": float(${TASK_START}),
    "export_time": time.time(),
    "initial_user_count": int(${INITIAL_USER_COUNT}),
    "current_user_count": current_user_count,
    "admin_exists": admin_exists,
    "imported_users": db_users,
    "python_scripts_found": scripts_found,
    "screenshot_path": "/tmp/final_screenshot.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Results written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="