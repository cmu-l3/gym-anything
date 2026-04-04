#!/bin/bash
# export_result.sh — oc_tb_contact_trace: TB Contact Tracing
# Queries registration, MALAR lab orders, and appointments for 3 TB contacts.

set -euo pipefail
echo "=== Exporting TB Contact Tracing Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/oc_tb_contact_trace_final_screenshot.png
echo "Final screenshot captured."

python3 << 'PYEOF'
import subprocess
import json

ADMIN  = ['/opt/openclinic/mysql5/bin/mysql', '-S', '/tmp/mysql5.sock', '-u', 'root', 'ocadmin_dbo',    '-N', '-e']
CLINIC = ['/opt/openclinic/mysql5/bin/mysql', '-S', '/tmp/mysql5.sock', '-u', 'root', 'openclinic_dbo', '-N', '-e']

def qa(sql):
    r = subprocess.run(ADMIN + [sql], capture_output=True, text=True)
    return r.stdout.strip()

def qc(sql):
    r = subprocess.run(CLINIC + [sql], capture_output=True, text=True)
    return r.stdout.strip()

def count_c(sql):
    val = qc(sql)
    try: return int(val)
    except: return -1

def find_pid(fname, lname):
    val = qa(f"SELECT personid FROM adminview WHERE firstname='{fname}' AND lastname='{lname}' LIMIT 1")
    try: return int(val)
    except: return None

def get_dob(pid):
    return qa(f"SELECT DATE(dateofbirth) FROM adminview WHERE personid={pid}")

contacts = [
    ("KOFI",    "ASANTE"),
    ("RANIA",   "AZIZ"),
    ("DIMITRI", "PAPADOPOULOS"),
]

result = {"task": "oc_tb_contact_trace"}

for fname, lname in contacts:
    key = fname.lower()
    pid = find_pid(fname, lname)
    result[f"{key}_pid"]   = pid
    result[f"{key}_dob"]   = get_dob(pid) if pid else None
    result[f"{key}_malar"] = count_c(f"SELECT COUNT(*) FROM requestedlabanalyses WHERE patientid={pid} AND analysiscode='MALAR'") if pid else 0
    result[f"{key}_appt"]  = count_c(f"SELECT COUNT(*) FROM oc_planning WHERE OC_PLANNING_PATIENTID={pid}") if pid else 0

RESULT_FILE = "/tmp/oc_tb_contact_trace_result.json"
with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {RESULT_FILE}")
for fname, lname in contacts:
    key = fname.lower()
    print(f"  {fname} {lname}: pid={result[f'{key}_pid']}, "
          f"dob={result[f'{key}_dob']}, malar={result[f'{key}_malar']}, appt={result[f'{key}_appt']}")
PYEOF

echo "=== Export Complete ==="
