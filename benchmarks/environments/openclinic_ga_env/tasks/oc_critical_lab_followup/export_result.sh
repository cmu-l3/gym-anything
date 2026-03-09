#!/bin/bash
# export_result.sh — oc_critical_lab_followup: Critical Lab Value Response Protocol
# Queries follow-up appointments and medication state for 3 critical-lab patients.

set -euo pipefail
echo "=== Exporting Critical Lab Value Response Protocol Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/oc_critical_lab_followup_final_screenshot.png
echo "Final screenshot captured."

python3 << 'PYEOF'
import subprocess
import json

MYSQL = ['/opt/openclinic/mysql5/bin/mysql', '-S', '/tmp/mysql5.sock', '-u', 'root', 'openclinic_dbo', '-N', '-e']

def q(sql):
    r = subprocess.run(MYSQL + [sql], capture_output=True, text=True)
    return r.stdout.strip()

def count(sql):
    val = q(sql)
    try: return int(val)
    except: return -1

result = {
    "task": "oc_critical_lab_followup",
    # Fatima (10003): critical GLUC=450
    "fatima_appt":       count("SELECT COUNT(*) FROM oc_planning WHERE OC_PLANNING_PATIENTID=10003"),
    "fatima_meds_total": count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10003"),
    "fatima_insulin":    count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10003 AND OC_CHRONICMED_PRODUCTID=9012"),
    # David (10004): critical CBC Hgb=6.1
    "david_appt":        count("SELECT COUNT(*) FROM oc_planning WHERE OC_PLANNING_PATIENTID=10004"),
    "david_folic_acid":  count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10004 AND OC_CHRONICMED_PRODUCTID=9011"),
    "david_meds_total":  count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10004"),
    "david_metformin":   count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10004 AND OC_CHRONICMED_PRODUCTID=9002"),
    # Li Wei (10009): critical CREAT=4.8
    "liwei_appt":        count("SELECT COUNT(*) FROM oc_planning WHERE OC_PLANNING_PATIENTID=10009"),
    "liwei_metformin":   count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10009 AND OC_CHRONICMED_PRODUCTID=9002"),
    "liwei_meds_total":  count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10009"),
}

RESULT_FILE = "/tmp/oc_critical_lab_followup_result.json"
with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {RESULT_FILE}")
print(f"  Fatima: appt={result['fatima_appt']}, insulin={result['fatima_insulin']}, meds={result['fatima_meds_total']}")
print(f"  David:  appt={result['david_appt']}, folic={result['david_folic_acid']}, meds={result['david_meds_total']}, metformin={result['david_metformin']}")
print(f"  Li Wei: appt={result['liwei_appt']}, metformin={result['liwei_metformin']}, meds={result['liwei_meds_total']}")
PYEOF

echo "=== Export Complete ==="
