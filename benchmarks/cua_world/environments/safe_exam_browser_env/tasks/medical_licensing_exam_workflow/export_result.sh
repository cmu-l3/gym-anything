#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting medical_licensing_exam_workflow results ==="

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
    with open('/tmp/seb_task_baseline_medical_licensing_exam_workflow.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_exam_count = baseline.get('exam_count', 0)
baseline_ind_count  = baseline.get('indicator_count', 0)
baseline_user_count = baseline.get('user_count', 0)

# ---- Criterion 1: Exam import ----
current_exam_count = int(db_query("SELECT COUNT(*) FROM exam") or 0)
new_exams = current_exam_count - baseline_exam_count

# Get newly imported exam IDs
new_exam_ids = []
if new_exams > 0:
    rows = db_query(
        f"SELECT id FROM exam ORDER BY id DESC LIMIT {new_exams}"
    )
    if rows:
        for row in rows.split('\n'):
            if row.strip():
                new_exam_ids.append(row.strip())

# ---- Criterion 2 & 3: Indicators on newly imported exams ----
all_exam_indicators = []
for exam_id in new_exam_ids:
    rows = db_query(
        f"SELECT id, name, type FROM indicator WHERE exam_id={exam_id}"
    )
    if rows:
        for row in rows.split('\n'):
            if row.strip():
                parts = row.strip().split('\t')
                if len(parts) >= 3:
                    all_exam_indicators.append({
                        'exam_id': exam_id,
                        'id': parts[0],
                        'name': parts[1],
                        'type': parts[2],
                    })

latency_monitor_found = any(
    ind['name'] == 'Latency Monitor' for ind in all_exam_indicators
)
integrity_alert_found = any(
    ind['name'] == 'Integrity Alert' for ind in all_exam_indicators
)
last_ping_on_exam = any(
    'PING' in ind['type'].upper() for ind in all_exam_indicators
)
warning_log_on_exam = any(
    'WARNING' in ind['type'].upper() for ind in all_exam_indicators
)

# ---- Criterion 4: User account ----
user_exists = int(db_query(
    "SELECT COUNT(*) FROM user WHERE username='med.proctor'"
) or 0)

user_active = False
user_role = ""
user_name_full = ""
user_email = ""
if user_exists > 0:
    uid = db_query("SELECT id FROM user WHERE username='med.proctor'")
    if uid:
        active_val = db_query(f"SELECT active FROM user WHERE id={uid}")
        user_active = (active_val == '1')
        user_role = db_query(f"SELECT user_role FROM user_role WHERE user_id={uid}") or ""
        user_name_full = db_query(
            f"SELECT CONCAT(name, ' ', surname) FROM user WHERE id={uid}"
        ) or ""
        user_email = db_query(f"SELECT email FROM user WHERE id={uid}") or ""

current_ind_count  = int(db_query("SELECT COUNT(*) FROM indicator") or 0)
current_user_count = int(db_query("SELECT COUNT(*) FROM user") or 0)

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    # C1
    'new_exams_imported': new_exams,
    'new_exam_ids': new_exam_ids,
    'baseline_exam_count': baseline_exam_count,
    'current_exam_count': current_exam_count,
    # C2 & C3
    'all_exam_indicators': all_exam_indicators,
    'indicator_count_on_new_exams': len(all_exam_indicators),
    'latency_monitor_found': latency_monitor_found,
    'integrity_alert_found': integrity_alert_found,
    'last_ping_type_on_exam': last_ping_on_exam,
    'warning_log_type_on_exam': warning_log_on_exam,
    'new_indicators_created': current_ind_count - baseline_ind_count,
    # C4
    'user_exists': user_exists > 0,
    'user_active': user_active,
    'user_role': user_role,
    'user_name_full': user_name_full,
    'user_email': user_email,
    'new_users_created': current_user_count - baseline_user_count,
}

with open('/tmp/medical_licensing_exam_workflow_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
