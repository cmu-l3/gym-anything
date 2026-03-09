#!/bin/bash
# export_result.sh — oc_pharma_audit: Pharmacy Medication Safety Audit
# Queries the current state of chronic medications for all 4 audit patients
# and writes the result to /tmp/oc_pharma_audit_result.json for the verifier.

set -euo pipefail
echo "=== Exporting Pharmacy Medication Safety Audit Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/oc_pharma_audit_final_screenshot.png
echo "Final screenshot captured."

# Query current chronic medication state for all 4 audit patients
python3 << 'PYEOF'
import subprocess
import json
import sys

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

result = {
    "task": "oc_pharma_audit",
    # C1: Amoxicillin (9001) for Fatima (10003) — should be 0 after fix
    "fatima_amox_count": count(
        "SELECT COUNT(*) FROM oc_chronicmedications "
        "WHERE OC_CHRONICMED_PATIENTID=10003 AND OC_CHRONICMED_PRODUCTID=9001"
    ),
    # C2: Amlodipine (9004) for Priya (10007) — should be exactly 1 after fix
    "priya_aml_count": count(
        "SELECT COUNT(*) FROM oc_chronicmedications "
        "WHERE OC_CHRONICMED_PATIENTID=10007 AND OC_CHRONICMED_PRODUCTID=9004"
    ),
    # C3: Metformin (9002) for Mohammed (10008) — should be 0 after fix
    "moham_met_count": count(
        "SELECT COUNT(*) FROM oc_chronicmedications "
        "WHERE OC_CHRONICMED_PATIENTID=10008 AND OC_CHRONICMED_PRODUCTID=9002"
    ),
    # C4: Atorvastatin (9005) for Li Wei (10009) — should be >= 1 (decoy: correct)
    "liwei_sta_count": count(
        "SELECT COUNT(*) FROM oc_chronicmedications "
        "WHERE OC_CHRONICMED_PATIENTID=10009 AND OC_CHRONICMED_PRODUCTID=9005"
    ),
    # Extra context: total chronic meds for each patient
    "fatima_total_meds": count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10003"),
    "priya_total_meds":  count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10007"),
    "moham_total_meds":  count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10008"),
    "liwei_total_meds":  count("SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10009"),
}

RESULT_FILE = "/tmp/oc_pharma_audit_result.json"
with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {RESULT_FILE}")
print(f"  Fatima Amoxicillin entries: {result['fatima_amox_count']} (want 0)")
print(f"  Priya Amlodipine entries:   {result['priya_aml_count']} (want 1)")
print(f"  Mohammed Metformin entries: {result['moham_met_count']} (want 0)")
print(f"  Li Wei Atorvastatin entries:{result['liwei_sta_count']} (want >=1)")
PYEOF

echo "=== Export Complete ==="
