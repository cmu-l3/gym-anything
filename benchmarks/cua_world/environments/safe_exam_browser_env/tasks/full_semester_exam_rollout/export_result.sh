#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting full_semester_exam_rollout results ==="

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

# Load baseline
baseline = {}
try:
    with open('/tmp/seb_task_baseline_full_semester_exam_rollout.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_cc_count    = baseline.get('connection_config_count', 0)
baseline_tmpl_count  = baseline.get('exam_template_count', 0)
baseline_ind_count   = baseline.get('indicator_count', 0)
baseline_user_count  = baseline.get('user_count', 0)

# ---- Criterion 1: Connection Config ----
cc_exists = int(db_query(
    "SELECT COUNT(*) FROM seb_client_configuration WHERE name='Finals Week Secure Config'"
) or 0)

cc_id = ""
cc_active = False
cc_fallback_url = ""
if cc_exists > 0:
    cc_id = db_query(
        "SELECT id FROM seb_client_configuration WHERE name='Finals Week Secure Config' ORDER BY id DESC LIMIT 1"
    )
    if cc_id:
        active_val = db_query(f"SELECT active FROM seb_client_configuration WHERE id={cc_id}")
        cc_active = (active_val == '1')
        cc_fallback_url = db_query(
            f"SELECT fallback_start_url FROM seb_client_configuration WHERE id={cc_id}"
        ) or ""

# ---- Criterion 2: Exam Template ----
tmpl_exists = int(db_query(
    "SELECT COUNT(*) FROM exam_template WHERE name='Final Examination Template'"
) or 0)

tmpl_id = ""
tmpl_description = ""
if tmpl_exists > 0:
    tmpl_id = db_query(
        "SELECT id FROM exam_template WHERE name='Final Examination Template' ORDER BY id DESC LIMIT 1"
    )
    if tmpl_id:
        tmpl_description = db_query(
            f"SELECT description FROM exam_template WHERE id={tmpl_id}"
        ) or ""

# ---- Criterion 3: Indicator on Template ----
indicators_on_template = []
if tmpl_id:
    rows = db_query(
        f"SELECT id, name, type FROM indicator WHERE exam_template_id={tmpl_id}"
    )
    if rows:
        for row in rows.split('\n'):
            if row.strip():
                parts = row.strip().split('\t')
                if len(parts) >= 3:
                    indicators_on_template.append({
                        'id': parts[0], 'name': parts[1], 'type': parts[2]
                    })

network_monitor_found = any(
    ind['name'] == 'Network Quality Monitor' for ind in indicators_on_template
)
last_ping_indicator = next(
    (ind for ind in indicators_on_template if 'PING' in ind['type'].upper()), None
)

# ---- Criterion 4: User Account ----
user_exists = int(db_query(
    "SELECT COUNT(*) FROM user WHERE username='exam.coordinator'"
) or 0)

user_active = False
user_name_full = ""
user_email = ""
user_role = ""
if user_exists > 0:
    uid = db_query("SELECT id FROM user WHERE username='exam.coordinator'")
    if uid:
        active_val = db_query(f"SELECT active FROM user WHERE id={uid}")
        user_active = (active_val == '1')
        user_name_full = db_query(
            f"SELECT CONCAT(name, ' ', surname) FROM user WHERE id={uid}"
        ) or ""
        user_email = db_query(f"SELECT email FROM user WHERE id={uid}") or ""
        user_role = db_query(f"SELECT user_role FROM user_role WHERE user_id={uid}") or ""

# ---- Delta counts ----
current_cc_count   = int(db_query("SELECT COUNT(*) FROM seb_client_configuration") or 0)
current_tmpl_count = int(db_query("SELECT COUNT(*) FROM exam_template") or 0)
current_ind_count  = int(db_query("SELECT COUNT(*) FROM indicator") or 0)
current_user_count = int(db_query("SELECT COUNT(*) FROM user") or 0)

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    # Criterion 1
    'connection_config_exists': cc_exists > 0,
    'connection_config_id': cc_id,
    'connection_config_active': cc_active,
    'connection_config_fallback_url': cc_fallback_url,
    'new_connection_configs_created': current_cc_count - baseline_cc_count,
    # Criterion 2
    'template_exists': tmpl_exists > 0,
    'template_id': tmpl_id,
    'template_description': tmpl_description,
    'new_templates_created': current_tmpl_count - baseline_tmpl_count,
    # Criterion 3
    'indicators_on_template': indicators_on_template,
    'indicator_count_on_template': len(indicators_on_template),
    'network_monitor_found': network_monitor_found,
    'last_ping_indicator': last_ping_indicator,
    'new_indicators_created': current_ind_count - baseline_ind_count,
    # Criterion 4
    'user_exists': user_exists > 0,
    'user_active': user_active,
    'user_name_full': user_name_full,
    'user_email': user_email,
    'user_role': user_role,
    'new_users_created': current_user_count - baseline_user_count,
}

with open('/tmp/full_semester_exam_rollout_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
