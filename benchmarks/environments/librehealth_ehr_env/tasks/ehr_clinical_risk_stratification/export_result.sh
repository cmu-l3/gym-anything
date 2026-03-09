#!/bin/bash
# export_result.sh — ehr_clinical_risk_stratification
set -e
source /workspace/scripts/task_utils.sh

echo "=== ehr_clinical_risk_stratification export ==="

python3 << 'PYEOF'
import json
import subprocess

def query(sql):
    try:
        out = subprocess.check_output(
            ['docker', 'exec', 'librehealth-db', 'mysql',
             '-u', 'libreehr', '-ps3cret', 'libreehr', '-N', '-e', sql],
            stderr=subprocess.DEVNULL
        ).decode('utf-8', errors='replace').strip()
        return out
    except Exception:
        return ''

try:
    with open('/tmp/lh_risk_gt.json') as f:
        gt = json.load(f)
except Exception:
    gt = {}

result = {
    "task_start":      gt.get('task_start', 0),
    "ground_truth":    gt,
    "patients_result": []
}

for patient in gt.get('patients', []):
    pid = patient['pid']

    # Retrieve all medical problems for this patient
    probs_raw = query(
        f"SELECT title FROM lists WHERE pid={pid} AND type='medical_problem' ORDER BY id"
    )
    problems = []
    if probs_raw:
        for line in probs_raw.split('\n'):
            t = line.strip()
            if t:
                problems.append(t)

    # Retrieve current appointment count
    appts_raw = query(
        f"SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid={pid}"
    )
    try:
        appt_count = int(appts_raw.strip())
    except Exception:
        appt_count = 0

    result['patients_result'].append({
        'pid':        pid,
        'fname':      patient.get('fname', ''),
        'lname':      patient.get('lname', ''),
        'problems':   problems,
        'prob_count': len(problems),
        'init_probs': patient.get('init_probs', 0),
        'appt_count': appt_count,
        'init_appts': patient.get('init_appts', 0)
    })

with open('/tmp/lh_risk_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Export complete: /tmp/lh_risk_result.json")
PYEOF

echo "=== export done ==="
exit 0
