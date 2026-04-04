#!/bin/bash
# export_result.sh — oc_complex_intake: Complex Patient Transfer Intake
# Queries registration, encounter, medications, labs, and appointments
# for Amara Nwosu and writes /tmp/oc_complex_intake_result.json.

set -euo pipefail
echo "=== Exporting Complex Patient Transfer Intake Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/oc_complex_intake_final_screenshot.png
echo "Final screenshot captured."

START_TS=$(cat /tmp/complex_intake_start_ts 2>/dev/null || date +%s)

python3 << PYEOF
import subprocess
import json
from datetime import datetime

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

start_ts = int("${START_TS}")
start_dt = datetime.fromtimestamp(start_ts).strftime('%Y-%m-%d %H:%M:%S')

# Find Amara Nwosu's personid
pid_str = qa("SELECT personid FROM adminview WHERE firstname='AMARA' AND lastname='NWOSU' LIMIT 1")
pid = None
try:
    pid = int(pid_str)
except:
    pass

result = {
    "task": "oc_complex_intake",
    "task_start_ts": start_ts,
    "start_dt": start_dt,
    "amara_pid": pid,
    "amara_dob": None,
    "amara_gender": None,
    "amara_hr_count": 0,
    "amara_metformin": 0,
    "amara_amlodipine": 0,
    "amara_hba1c_new": 0,
    "amara_creat_new": 0,
    "amara_appt_count": 0,
}

if pid:
    dob_row = qa(f"SELECT DATE(dateofbirth), gender FROM adminview WHERE personid={pid}")
    parts = dob_row.split('\t') if '\t' in dob_row else dob_row.split()
    if len(parts) >= 2:
        result["amara_dob"] = parts[0].strip()
        result["amara_gender"] = parts[1].strip().upper()
    elif len(parts) == 1:
        result["amara_dob"] = parts[0].strip()

    result["amara_hr_count"]  = count_c(f"SELECT COUNT(*) FROM healthrecord WHERE personId={pid}")
    result["amara_metformin"]  = count_c(f"SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID={pid} AND OC_CHRONICMED_PRODUCTID=9002")
    result["amara_amlodipine"] = count_c(f"SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID={pid} AND OC_CHRONICMED_PRODUCTID=9004")
    result["amara_hba1c_new"]  = count_c(f"SELECT COUNT(*) FROM requestedlabanalyses WHERE patientid={pid} AND analysiscode='HBA1C' AND requestdatetime >= '{start_dt}'")
    result["amara_creat_new"]  = count_c(f"SELECT COUNT(*) FROM requestedlabanalyses WHERE patientid={pid} AND analysiscode='CREAT' AND requestdatetime >= '{start_dt}'")
    result["amara_appt_count"] = count_c(f"SELECT COUNT(*) FROM oc_planning WHERE OC_PLANNING_PATIENTID={pid}")

RESULT_FILE = "/tmp/oc_complex_intake_result.json"
with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {RESULT_FILE}")
if pid:
    print(f"  Amara Nwosu found: ID={pid}")
    print(f"  DOB={result['amara_dob']}, Gender={result['amara_gender']}")
    print(f"  Health records: {result['amara_hr_count']}")
    print(f"  Metformin: {result['amara_metformin']}, Amlodipine: {result['amara_amlodipine']}")
    print(f"  HBA1C: {result['amara_hba1c_new']}, CREAT: {result['amara_creat_new']}")
    print(f"  Appointments: {result['amara_appt_count']}")
else:
    print("  Amara Nwosu NOT found in patient registry")
PYEOF

echo "=== Export Complete ==="
