#!/bin/bash
echo "=== Exporting multi_user_energy_monitoring_setup result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_multiuser_final.png

python3 << 'PYEOF'
import subprocess, json

def db(sql):
    r = subprocess.run(
        ['docker', 'exec', 'emoncms-db', 'mysql', '-u', 'emoncms', '-pemoncms', 'emoncms', '-N', '-e', sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

try:
    with open('/tmp/task_start_timestamp') as f:
        task_start = int(f.read().strip() or 0)
except Exception:
    task_start = 0

def check_user(username):
    """Return a dict with all relevant state for a tenant user."""
    user_row = db(f"SELECT id, email, apikey_write, apikey_read FROM users WHERE username='{username}'")
    if not user_row.strip():
        return {
            'exists': False,
            'userid': None,
            'email': '',
            'input_count': 0,
            'inputs_with_process': 0,
            'feed_count': 0,
            'dashboard_count': 0,
        }

    parts = user_row.split('\n')[0].split('\t')
    userid    = int(parts[0]) if parts[0].isdigit() else None
    email     = parts[1] if len(parts) > 1 else ''
    apikey_w  = parts[2] if len(parts) > 2 else ''
    apikey_r  = parts[3] if len(parts) > 3 else ''

    if not userid:
        return {'exists': False, 'userid': None, 'email': email,
                'input_count': 0, 'inputs_with_process': 0,
                'feed_count': 0, 'dashboard_count': 0}

    input_count = int(db(f"SELECT COUNT(*) FROM input WHERE userid={userid}") or 0)
    inputs_with_process = int(db(
        f"SELECT COUNT(*) FROM input WHERE userid={userid} "
        f"AND processList IS NOT NULL AND processList != ''"
    ) or 0)
    feed_count = int(db(f"SELECT COUNT(*) FROM feeds WHERE userid={userid}") or 0)
    dashboard_count = int(db(f"SELECT COUNT(*) FROM dashboard WHERE userid={userid}") or 0)

    return {
        'exists': True,
        'userid': userid,
        'email': email,
        'input_count': input_count,
        'inputs_with_process': inputs_with_process,
        'feed_count': feed_count,
        'dashboard_count': dashboard_count,
    }

tenant_a = check_user('tenant_a')
tenant_b = check_user('tenant_b')

result = {
    'task_start': task_start,
    'tenant_a': tenant_a,
    'tenant_b': tenant_b,
}

with open('/tmp/multi_user_energy_monitoring_setup_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
