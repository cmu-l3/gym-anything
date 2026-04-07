#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting certification_exam_infrastructure_setup results ==="

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

start_time = float(open('/tmp/task_start_time.txt').read().strip())

# Load baseline
baseline = {}
try:
    with open('/tmp/seb_task_baseline_certification_exam_infrastructure_setup.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_ec_count   = baseline.get('exam_config_count', 0)
baseline_cc_count   = baseline.get('connection_config_count', 0)
baseline_tmpl_count = baseline.get('exam_template_count', 0)
baseline_ind_count  = baseline.get('indicator_count', 0)
baseline_user_count = baseline.get('user_count', 0)

# ---- C1: Exam Configuration ----
ec_exists = int(db_query(
    "SELECT COUNT(*) FROM configuration_node WHERE name='Professional Certification Lockdown' AND type='EXAM_CONFIG'"
) or 0)

ec_id = ""
ec_description = ""
config_values = {}
if ec_exists > 0:
    ec_id = db_query(
        "SELECT id FROM configuration_node WHERE name='Professional Certification Lockdown' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1"
    )
    if ec_id:
        ec_description = db_query(
            f"SELECT description FROM configuration_node WHERE id={ec_id}"
        ) or ""
        # Query EAV configuration values
        config_version_id = db_query(
            f"SELECT id FROM configuration WHERE configuration_node_id={ec_id} ORDER BY id DESC LIMIT 1"
        )
        if config_version_id:
            rows = db_query(
                f"SELECT CONCAT(ca.name, '\t', IFNULL(cv.value, 'NULL')) "
                f"FROM configuration_value cv "
                f"JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id "
                f"WHERE cv.configuration_id = {config_version_id} "
                f"ORDER BY ca.name"
            )
            for line in rows.split('\n'):
                if '\t' in line:
                    key, val = line.split('\t', 1)
                    config_values[key.strip()] = val.strip()

# ---- C2: Exam Template ----
tmpl_exists = int(db_query(
    "SELECT COUNT(*) FROM exam_template WHERE name='Proctored Certification Template'"
) or 0)

tmpl_id = ""
tmpl_description = ""
if tmpl_exists > 0:
    tmpl_id = db_query(
        "SELECT id FROM exam_template WHERE name='Proctored Certification Template' ORDER BY id DESC LIMIT 1"
    )
    if tmpl_id:
        tmpl_description = db_query(
            f"SELECT description FROM exam_template WHERE id={tmpl_id}"
        ) or ""

# ---- C3: Indicators on Template ----
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
                    ind = {'id': parts[0], 'name': parts[1], 'type': parts[2]}
                    # Query thresholds for this indicator
                    thresh_rows = db_query(
                        f"SELECT color, value FROM threshold WHERE indicator_id={parts[0]}"
                    )
                    thresholds = []
                    if thresh_rows:
                        for tr in thresh_rows.split('\n'):
                            if tr.strip():
                                tparts = tr.strip().split('\t')
                                if len(tparts) >= 2:
                                    thresholds.append({
                                        'color': tparts[0],
                                        'value': tparts[1]
                                    })
                    ind['thresholds'] = thresholds
                    indicators_on_template.append(ind)

connection_watchdog = next(
    (ind for ind in indicators_on_template if ind['name'] == 'Connection Watchdog'), None
)
security_event_monitor = next(
    (ind for ind in indicators_on_template if ind['name'] == 'Security Event Monitor'), None
)
last_ping_indicator = next(
    (ind for ind in indicators_on_template if 'PING' in ind['type'].upper()), None
)
error_log_indicator = next(
    (ind for ind in indicators_on_template if 'ERROR' in ind['type'].upper()), None
)

# ---- C4: Connection Configuration ----
cc_exists = int(db_query(
    "SELECT COUNT(*) FROM seb_client_configuration WHERE name='Certification Center Link'"
) or 0)

cc_id = ""
cc_active = False
cc_fallback_url = ""
if cc_exists > 0:
    cc_id = db_query(
        "SELECT id FROM seb_client_configuration WHERE name='Certification Center Link' ORDER BY id DESC LIMIT 1"
    )
    if cc_id:
        active_val = db_query(f"SELECT active FROM seb_client_configuration WHERE id={cc_id}")
        cc_active = (active_val == '1')
        cc_fallback_url = db_query(
            f"SELECT fallback_start_url FROM seb_client_configuration WHERE id={cc_id}"
        ) or ""

# ---- C5: User Account ----
user_exists = int(db_query(
    "SELECT COUNT(*) FROM user WHERE username='lead.proctor'"
) or 0)

user_active = False
user_name_full = ""
user_email = ""
user_role = ""
if user_exists > 0:
    uid = db_query("SELECT id FROM user WHERE username='lead.proctor'")
    if uid:
        active_val = db_query(f"SELECT active FROM user WHERE id={uid}")
        user_active = (active_val == '1')
        user_name_full = db_query(
            f"SELECT CONCAT(name, ' ', surname) FROM user WHERE id={uid}"
        ) or ""
        user_email = db_query(f"SELECT email FROM user WHERE id={uid}") or ""
        user_role = db_query(f"SELECT user_role FROM user_role WHERE user_id={uid}") or ""

# ---- Delta counts ----
current_ec_count   = int(db_query("SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'") or 0)
current_cc_count   = int(db_query("SELECT COUNT(*) FROM seb_client_configuration") or 0)
current_tmpl_count = int(db_query("SELECT COUNT(*) FROM exam_template") or 0)
current_ind_count  = int(db_query("SELECT COUNT(*) FROM indicator") or 0)
current_user_count = int(db_query("SELECT COUNT(*) FROM user") or 0)

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    # C1: Exam config
    'exam_config_exists': ec_exists > 0,
    'exam_config_id': ec_id,
    'exam_config_description': ec_description,
    'config_values': config_values,
    'new_exam_configs_created': current_ec_count - baseline_ec_count,
    # C2: Exam template
    'template_exists': tmpl_exists > 0,
    'template_id': tmpl_id,
    'template_description': tmpl_description,
    'new_templates_created': current_tmpl_count - baseline_tmpl_count,
    # C3: Indicators
    'indicators_on_template': indicators_on_template,
    'indicator_count_on_template': len(indicators_on_template),
    'connection_watchdog_found': connection_watchdog is not None,
    'connection_watchdog': connection_watchdog,
    'security_event_monitor_found': security_event_monitor is not None,
    'security_event_monitor': security_event_monitor,
    'last_ping_indicator': last_ping_indicator,
    'error_log_indicator': error_log_indicator,
    'new_indicators_created': current_ind_count - baseline_ind_count,
    # C4: Connection config
    'connection_config_exists': cc_exists > 0,
    'connection_config_id': cc_id,
    'connection_config_active': cc_active,
    'connection_config_fallback_url': cc_fallback_url,
    'new_connection_configs_created': current_cc_count - baseline_cc_count,
    # C5: User
    'user_exists': user_exists > 0,
    'user_active': user_active,
    'user_name_full': user_name_full,
    'user_email': user_email,
    'user_role': user_role,
    'new_users_created': current_user_count - baseline_user_count,
}

result_path = '/tmp/certification_exam_infrastructure_setup_result.json'

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
