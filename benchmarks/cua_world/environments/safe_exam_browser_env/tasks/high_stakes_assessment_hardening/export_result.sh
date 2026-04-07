#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting high_stakes_assessment_hardening results ==="

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
    with open('/tmp/seb_task_baseline_high_stakes_assessment_hardening.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_ec_count   = baseline.get('exam_config_count', 0)
baseline_cc_count   = baseline.get('connection_config_count', 0)
baseline_tmpl_count = baseline.get('exam_template_count', 0)
baseline_ind_count  = baseline.get('indicator_count', 0)

# ---- Criterion 1: Exam Configuration ----
ec_exists = int(db_query(
    "SELECT COUNT(*) FROM configuration_node "
    "WHERE name='CPA Board Exam - Maximum Security' AND type='EXAM_CONFIG'"
) or 0)

ec_id = ""
if ec_exists > 0:
    ec_id = db_query(
        "SELECT id FROM configuration_node "
        "WHERE name='CPA Board Exam - Maximum Security' AND type='EXAM_CONFIG' "
        "ORDER BY id DESC LIMIT 1"
    )

# ---- Criterion 2: Connection Configuration ----
cc_exists = int(db_query(
    "SELECT COUNT(*) FROM seb_client_configuration WHERE name='CPA Exam Connection'"
) or 0)

cc_id = ""
cc_active = False
if cc_exists > 0:
    cc_id = db_query(
        "SELECT id FROM seb_client_configuration WHERE name='CPA Exam Connection' "
        "ORDER BY id DESC LIMIT 1"
    )
    if cc_id:
        active_val = db_query(
            f"SELECT active FROM seb_client_configuration WHERE id={cc_id}"
        )
        cc_active = (active_val == '1')

# ---- Criterion 3 & 4: Exam Template + Indicators ----
tmpl_exists = int(db_query(
    "SELECT COUNT(*) FROM exam_template WHERE name='CPA Board Exam Template'"
) or 0)

tmpl_id = ""
indicators_on_template = []
if tmpl_exists > 0:
    tmpl_id = db_query(
        "SELECT id FROM exam_template WHERE name='CPA Board Exam Template' "
        "ORDER BY id DESC LIMIT 1"
    )
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

# Check individual indicator names
connection_monitor_found = any(
    ind['name'] == 'Connection Monitor' for ind in indicators_on_template
)
security_alert_found = any(
    ind['name'] == 'Security Alert Monitor' for ind in indicators_on_template
)
last_ping_found = any(
    'PING' in ind['type'].upper() for ind in indicators_on_template
)
error_log_found = any(
    'ERROR' in ind['type'].upper() for ind in indicators_on_template
)

current_ec_count   = int(db_query("SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'") or 0)
current_cc_count   = int(db_query("SELECT COUNT(*) FROM seb_client_configuration") or 0)
current_tmpl_count = int(db_query("SELECT COUNT(*) FROM exam_template") or 0)
current_ind_count  = int(db_query("SELECT COUNT(*) FROM indicator") or 0)

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    # C1
    'exam_config_exists': ec_exists > 0,
    'exam_config_id': ec_id,
    'new_exam_configs_created': current_ec_count - baseline_ec_count,
    # C2
    'connection_config_exists': cc_exists > 0,
    'connection_config_id': cc_id,
    'connection_config_active': cc_active,
    'new_connection_configs_created': current_cc_count - baseline_cc_count,
    # C3
    'template_exists': tmpl_exists > 0,
    'template_id': tmpl_id,
    'new_templates_created': current_tmpl_count - baseline_tmpl_count,
    # C4 (indicators)
    'indicators_on_template': indicators_on_template,
    'indicator_count_on_template': len(indicators_on_template),
    'connection_monitor_found': connection_monitor_found,
    'security_alert_found': security_alert_found,
    'last_ping_type_found': last_ping_found,
    'error_log_type_found': error_log_found,
    'new_indicators_created': current_ind_count - baseline_ind_count,
}

with open('/tmp/high_stakes_assessment_hardening_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
