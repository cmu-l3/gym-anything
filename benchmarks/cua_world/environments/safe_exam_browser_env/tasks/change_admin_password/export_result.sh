#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting change_admin_password results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()

start_time = 0
if os.path.exists('/tmp/task_start_time.txt'):
    start_time = float(open('/tmp/task_start_time.txt').read().strip())

initial_hash = ""
if os.path.exists('/tmp/initial_admin_hash.txt'):
    initial_hash = open('/tmp/initial_admin_hash.txt').read().strip()

# Query current user details from the database
current_hash = db_query("SELECT password FROM user WHERE username='super-admin';")
current_name = db_query("SELECT name FROM user WHERE username='super-admin';")
current_surname = db_query("SELECT surname FROM user WHERE username='super-admin';")
current_email = db_query("SELECT email FROM user WHERE username='super-admin';")
current_timezone = db_query("SELECT time_zone FROM user WHERE username='super-admin';")
current_language = db_query("SELECT language FROM user WHERE username='super-admin';")

# Attempt API authentication check using basic auth
# Note: This is a secondary signal. SEB Server may or may not allow basic auth natively on all endpoints, 
# but we check if we get a definitive 200 or 401 difference.
auth_old_cmd = subprocess.run(['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', '-u', 'super-admin:admin', 'http://localhost:8080/api/user/current'], capture_output=True, text=True)
auth_new_cmd = subprocess.run(['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', '-u', 'super-admin:SEB_Secure#2024', 'http://localhost:8080/api/user/current'], capture_output=True, text=True)

auth_old_code = auth_old_cmd.stdout.strip()
auth_new_code = auth_new_cmd.stdout.strip()

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'db_state': {
        'initial_password_hash': initial_hash,
        'current_password_hash': current_hash,
        'hash_changed': initial_hash != current_hash and bool(current_hash) and initial_hash != "unknown",
        'name': current_name,
        'surname': current_surname,
        'email': current_email,
        'time_zone': current_timezone,
        'language': current_language
    },
    'api_auth': {
        'old_password_http_code': auth_old_code,
        'new_password_http_code': auth_new_code
    },
    'firefox_running': firefox_running
}

with open('/tmp/change_admin_password_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="