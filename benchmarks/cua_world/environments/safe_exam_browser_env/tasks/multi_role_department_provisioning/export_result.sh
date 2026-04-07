#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting multi_role_department_provisioning results ==="

take_screenshot /tmp/final_screenshot.png

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

baseline = {}
try:
    with open('/tmp/seb_task_baseline_multi_role_department_provisioning.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_user_count = baseline.get('user_count', 0)
baseline_cc_count   = baseline.get('connection_config_count', 0)

# ---- User accounts ----
expected_users = {
    'cs.admin': 'EXAM_ADMIN',
    'math.admin': 'EXAM_ADMIN',
    'physics.supporter': 'EXAM_SUPPORTER',
    'it.supervisor': 'INSTITUTIONAL_ADMIN',
}

users_found = {}
user_details = {}

for username in expected_users:
    count = db_query(f"SELECT COUNT(*) FROM user WHERE username='{username}'")
    found = int(count) > 0 if count else False
    users_found[username] = found

    if found:
        uid = db_query(f"SELECT id FROM user WHERE username='{username}'")
        if uid:
            active_val = db_query(f"SELECT active FROM user WHERE id={uid}")
            role_val   = db_query(f"SELECT user_role FROM user_role WHERE user_id={uid}") or ""
            name_val   = db_query(
                f"SELECT CONCAT(name, ' ', surname) FROM user WHERE id={uid}"
            ) or ""
            email_val  = db_query(f"SELECT email FROM user WHERE id={uid}") or ""
            user_details[username] = {
                'active': (active_val == '1'),
                'role': role_val,
                'name': name_val,
                'email': email_val,
            }

# ---- Connection Configuration ----
cc_exists = int(db_query(
    "SELECT COUNT(*) FROM seb_client_configuration WHERE name='Department Hub Connection Config'"
) or 0)

cc_id = ""
cc_active = False
if cc_exists > 0:
    cc_id = db_query(
        "SELECT id FROM seb_client_configuration WHERE name='Department Hub Connection Config' "
        "ORDER BY id DESC LIMIT 1"
    )
    if cc_id:
        active_val = db_query(
            f"SELECT active FROM seb_client_configuration WHERE id={cc_id}"
        )
        cc_active = (active_val == '1')

current_user_count = int(db_query("SELECT COUNT(*) FROM user") or 0)
current_cc_count   = int(db_query("SELECT COUNT(*) FROM seb_client_configuration") or 0)

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'users_found': users_found,
    'user_details': user_details,
    'all_four_users_created': all(users_found.values()),
    'users_created_count': sum(1 for v in users_found.values() if v),
    'new_users_created': current_user_count - baseline_user_count,
    'baseline_user_count': baseline_user_count,
    'current_user_count': current_user_count,
    'connection_config_exists': cc_exists > 0,
    'connection_config_id': cc_id,
    'connection_config_active': cc_active,
    'new_connection_configs_created': current_cc_count - baseline_cc_count,
}

with open('/tmp/multi_role_department_provisioning_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
