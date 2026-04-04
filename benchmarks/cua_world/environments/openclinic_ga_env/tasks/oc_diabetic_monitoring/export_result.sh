#!/bin/bash
# export_result.sh — oc_diabetic_monitoring: Diabetes HbA1c Compliance Audit
# Queries HbA1c order counts for each patient AFTER the task start timestamp,
# writes result to /tmp/oc_diabetic_monitoring_result.json for the verifier.

set -euo pipefail
echo "=== Exporting Diabetes HbA1c Compliance Audit Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/oc_diabetic_monitoring_final_screenshot.png
echo "Final screenshot captured."

# Read task start timestamp
START_TS=$(cat /tmp/diabetic_task_start_ts 2>/dev/null || date +%s)

python3 << PYEOF
import subprocess
import json
import sys
from datetime import datetime

MYSQL = ['/opt/openclinic/mysql5/bin/mysql', '-S', '/tmp/mysql5.sock', '-u', 'root', 'openclinic_dbo', '-N', '-e']

def q(sql):
    r = subprocess.run(MYSQL + [sql], capture_output=True, text=True)
    return r.stdout.strip()

def count(sql):
    val = q(sql)
    try:
        return int(val)
    except (ValueError, TypeError):
        return -1

start_ts = int("${START_TS}")
start_dt = datetime.fromtimestamp(start_ts).strftime('%Y-%m-%d %H:%M:%S')

def new_hba1c(pid):
    """Count HbA1c orders placed AFTER task start (agent's work)."""
    return count(
        f"SELECT COUNT(*) FROM requestedlabanalyses "
        f"WHERE patientid={pid} AND analysiscode='HBA1C' "
        f"AND requestdatetime >= '{start_dt}'"
    )

result = {
    "task": "oc_diabetic_monitoring",
    "task_start_ts": start_ts,
    "start_dt": start_dt,
    # New HbA1c orders placed by agent
    "ana_hba1c_new":   new_hba1c(10001),
    "maria_hba1c_new": new_hba1c(10005),
    "priya_hba1c_new": new_hba1c(10007),
    "elena_hba1c_new": new_hba1c(10010),
    # Total HbA1c orders (including pre-seeded) for context
    "ana_hba1c_total":   count("SELECT COUNT(*) FROM requestedlabanalyses WHERE patientid=10001 AND analysiscode='HBA1C'"),
    "maria_hba1c_total": count("SELECT COUNT(*) FROM requestedlabanalyses WHERE patientid=10005 AND analysiscode='HBA1C'"),
    "priya_hba1c_total": count("SELECT COUNT(*) FROM requestedlabanalyses WHERE patientid=10007 AND analysiscode='HBA1C'"),
    "elena_hba1c_total": count("SELECT COUNT(*) FROM requestedlabanalyses WHERE patientid=10010 AND analysiscode='HBA1C'"),
}

RESULT_FILE = "/tmp/oc_diabetic_monitoring_result.json"
with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {RESULT_FILE}")
print(f"  New HbA1c orders after task start ({start_dt}):")
print(f"    Ana Ferreira (10001):   {result['ana_hba1c_new']} (want >=1)")
print(f"    Maria Santos (10005):   {result['maria_hba1c_new']} (want >=1)")
print(f"    Priya Sharma (10007):   {result['priya_hba1c_new']} (want >=1)")
print(f"    Elena Popescu (10010):  {result['elena_hba1c_new']} (want 0)")
PYEOF

echo "=== Export Complete ==="
