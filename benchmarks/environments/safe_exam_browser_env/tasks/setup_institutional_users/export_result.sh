#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting setup_institutional_users results ==="

take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

python3 << 'PYEOF'
import json
import time
import subprocess

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()

start_time = float(open('/tmp/task_start_time.txt').read().strip())

# Load baseline
baseline = {}
try:
    with open('/tmp/seb_task_baseline_setup_institutional_users.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_user_count = baseline.get('user_count', 0)

# Check for each expected user
users_found = {}
for username in ['prof.martinez', 'ta.chen', 'admin.thompson']:
    count = db_query(f"SELECT COUNT(*) FROM user WHERE username='{username}'")
    users_found[username] = int(count) > 0 if count else False

# Get user details
user_details = {}
for username in ['prof.martinez', 'ta.chen', 'admin.thompson']:
    if users_found[username]:
        name = db_query(f"SELECT CONCAT(name, ' ', surname) FROM user WHERE username='{username}'")
        email = db_query(f"SELECT email FROM user WHERE username='{username}'")
        active = db_query(f"SELECT active FROM user WHERE username='{username}'")
        user_details[username] = {
            'name': name,
            'email': email,
            'active': active == '1' if active else False,
        }

# Count total users now vs baseline
current_user_count = int(db_query("SELECT COUNT(*) FROM user") or 0)
new_users = current_user_count - baseline_user_count

# Check roles via user_role table
user_roles = {}
for username in ['prof.martinez', 'ta.chen', 'admin.thompson']:
    if users_found[username]:
        user_id = db_query(f"SELECT id FROM user WHERE username='{username}'")
        if user_id:
            role = db_query(f"SELECT user_role FROM user_role WHERE user_id={user_id}")
            user_roles[username] = role

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'users_found': users_found,
    'user_details': user_details,
    'user_roles': user_roles,
    'new_users_created': new_users,
    'baseline_user_count': baseline_user_count,
    'current_user_count': current_user_count,
    'all_users_created': all(users_found.values()),
    'firefox_running': firefox_running,
}

with open('/tmp/setup_institutional_users_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
