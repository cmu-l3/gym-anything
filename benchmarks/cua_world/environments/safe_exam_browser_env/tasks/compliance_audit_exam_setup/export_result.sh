#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting compliance_audit_exam_setup results ==="

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
    with open('/tmp/seb_task_baseline_compliance_audit_exam_setup.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_ec_count   = baseline.get('exam_config_count', 0)
baseline_cc_count   = baseline.get('connection_config_count', 0)
baseline_tmpl_count = baseline.get('exam_template_count', 0)
baseline_ind_count  = baseline.get('indicator_count', 0)
baseline_user_count = baseline.get('user_count', 0)

# ---- Criterion 1: Exam Configuration with GDPR description ----
ec_exists = int(db_query(
    "SELECT COUNT(*) FROM configuration_node "
    "WHERE name='GDPR Compliant Exam Config' AND type='EXAM_CONFIG'"
) or 0)

ec_id = ""
ec_description = ""
if ec_exists > 0:
    ec_id = db_query(
        "SELECT id FROM configuration_node "
        "WHERE name='GDPR Compliant Exam Config' AND type='EXAM_CONFIG' "
        "ORDER BY id DESC LIMIT 1"
    )
    if ec_id:
        ec_description = db_query(
            f"SELECT description FROM configuration_node WHERE id={ec_id}"
        ) or ""

# ---- Criterion 2: Connection Configuration ----
cc_exists = int(db_query(
    "SELECT COUNT(*) FROM seb_client_configuration WHERE name='Privacy-First Connection'"
) or 0)

cc_id = ""
cc_active = False
cc_fallback_url = ""
if cc_exists > 0:
    cc_id = db_query(
        "SELECT id FROM seb_client_configuration WHERE name='Privacy-First Connection' "
        "ORDER BY id DESC LIMIT 1"
    )
    if cc_id:
        active_val = db_query(
            f"SELECT active FROM seb_client_configuration WHERE id={cc_id}"
        )
        cc_active = (active_val == '1')
        cc_fallback_url = db_query(
            f"SELECT fallback_start_url FROM seb_client_configuration WHERE id={cc_id}"
        ) or ""

# ---- Criterion 3: Exam Template ----
tmpl_exists = int(db_query(
    "SELECT COUNT(*) FROM exam_template WHERE name='GDPR Exam Template'"
) or 0)

tmpl_id = ""
if tmpl_exists > 0:
    tmpl_id = db_query(
        "SELECT id FROM exam_template WHERE name='GDPR Exam Template' "
        "ORDER BY id DESC LIMIT 1"
    )

# Indicator on template
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

minimal_monitoring_found = any(
    ind['name'] == 'Minimal Monitoring' for ind in indicators_on_template
)
last_ping_found = any(
    'PING' in ind['type'].upper() for ind in indicators_on_template
)

# ---- Criterion 4: User Account ----
user_exists = int(db_query(
    "SELECT COUNT(*) FROM user WHERE username='dpo.officer'"
) or 0)

user_active = False
user_role = ""
user_name_full = ""
user_email = ""
if user_exists > 0:
    uid = db_query("SELECT id FROM user WHERE username='dpo.officer'")
    if uid:
        active_val = db_query(f"SELECT active FROM user WHERE id={uid}")
        user_active = (active_val == '1')
        user_role = db_query(f"SELECT user_role FROM user_role WHERE user_id={uid}") or ""
        user_name_full = db_query(
            f"SELECT CONCAT(name, ' ', surname) FROM user WHERE id={uid}"
        ) or ""
        user_email = db_query(f"SELECT email FROM user WHERE id={uid}") or ""

current_ec_count   = int(db_query("SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'") or 0)
current_cc_count   = int(db_query("SELECT COUNT(*) FROM seb_client_configuration") or 0)
current_tmpl_count = int(db_query("SELECT COUNT(*) FROM exam_template") or 0)
current_ind_count  = int(db_query("SELECT COUNT(*) FROM indicator") or 0)
current_user_count = int(db_query("SELECT COUNT(*) FROM user") or 0)

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    # C1
    'exam_config_exists': ec_exists > 0,
    'exam_config_id': ec_id,
    'exam_config_description': ec_description,
    'new_exam_configs_created': current_ec_count - baseline_ec_count,
    # C2
    'connection_config_exists': cc_exists > 0,
    'connection_config_id': cc_id,
    'connection_config_active': cc_active,
    'connection_config_fallback_url': cc_fallback_url,
    'new_connection_configs_created': current_cc_count - baseline_cc_count,
    # C3
    'template_exists': tmpl_exists > 0,
    'template_id': tmpl_id,
    'new_templates_created': current_tmpl_count - baseline_tmpl_count,
    'indicators_on_template': indicators_on_template,
    'indicator_count_on_template': len(indicators_on_template),
    'minimal_monitoring_found': minimal_monitoring_found,
    'last_ping_type_found': last_ping_found,
    'new_indicators_created': current_ind_count - baseline_ind_count,
    # C4
    'user_exists': user_exists > 0,
    'user_active': user_active,
    'user_role': user_role,
    'user_name_full': user_name_full,
    'user_email': user_email,
    'new_users_created': current_user_count - baseline_user_count,
}

with open('/tmp/compliance_audit_exam_setup_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
