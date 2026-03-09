#!/bin/bash
# Export script for Complete Patient Profile task in OSCAR EMR

echo "=== Exporting Complete Patient Profile Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

PATIENT_NO=$(cat /tmp/task_patient_no_profile 2>/dev/null || oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Jean-Pierre' AND last_name='Bouchard' LIMIT 1")
INITIAL_ALLERGY_COUNT=$(cat /tmp/initial_allergy_count_profile 2>/dev/null || echo "0")
INITIAL_DRUG_COUNT=$(cat /tmp/initial_drug_count_profile 2>/dev/null || echo "0")

echo "Patient demographic_no: $PATIENT_NO"

python3 << PYEOF
import json, subprocess

patient_no = "${PATIENT_NO}"
initial_allergies = int("${INITIAL_ALLERGY_COUNT}".strip() or "0")
initial_drugs = int("${INITIAL_DRUG_COUNT}".strip() or "0")

def run_query(q):
    try:
        r = subprocess.run(
            ['docker', 'exec', 'oscar-db', 'mysql', '-u', 'oscar', '-poscar', 'oscar', '-N', '-e', q],
            capture_output=True, text=True, timeout=15
        )
        return r.stdout.strip()
    except Exception:
        return ""

# Query allergies
allergy_rows = run_query(f"SELECT DESCRIPTION, reaction, severity_of_reaction, archived FROM allergies WHERE demographic_no={patient_no} ORDER BY ALLERGY_ID DESC")
# Query medications (active only)
drug_rows = run_query(f"SELECT GN, BN, dosage, freqcode, archived FROM drugs WHERE demographic_no={patient_no} ORDER BY drugid DESC")

current_active_allergies = int(run_query(f"SELECT COUNT(*) FROM allergies WHERE demographic_no={patient_no} AND archived=0") or "0")
current_active_drugs = int(run_query(f"SELECT COUNT(*) FROM drugs WHERE demographic_no={patient_no} AND archived=0") or "0")

# Parse allergies
allergy_list = []
has_penicillin = False
has_sulfa = False
penicillin_severe = False

for line in allergy_rows.splitlines():
    parts = line.split('\t')
    if len(parts) >= 3:
        desc = parts[0].strip().lower()
        reaction = parts[1].strip().lower() if len(parts) > 1 else ''
        severity = parts[2].strip().lower() if len(parts) > 2 else ''
        archived = parts[3].strip() if len(parts) > 3 else '0'
        if archived == '0':
            allergy_list.append({'description': parts[0], 'reaction': parts[1] if len(parts)>1 else '', 'severity': parts[2] if len(parts)>2 else ''})
            if 'penicillin' in desc or 'pcn' in desc or 'amoxicillin' in desc:
                has_penicillin = True
                if severity in ('s', 'severe', 'se') or 'severe' in severity or 'anaphyl' in reaction:
                    penicillin_severe = True
            if 'sulfa' in desc or 'sulfonamide' in desc or 'sulfameth' in desc or 'trimethoprim' in desc:
                has_sulfa = True

# Parse medications
drug_list = []
has_metformin = False
has_ramipril = False
metformin_dose_ok = False
ramipril_dose_ok = False

for line in drug_rows.splitlines():
    parts = line.split('\t')
    if len(parts) >= 1:
        gn = parts[0].strip().lower()
        bn = parts[1].strip().lower() if len(parts) > 1 else ''
        dosage = parts[2].strip() if len(parts) > 2 else ''
        freq = parts[3].strip().lower() if len(parts) > 3 else ''
        archived = parts[4].strip() if len(parts) > 4 else '0'
        if archived == '0':
            drug_list.append({'gn': parts[0], 'dosage': dosage, 'freq': freq})
            if 'metformin' in gn or 'metformin' in bn or 'glucophage' in bn:
                has_metformin = True
                if '500' in dosage:
                    metformin_dose_ok = True
            if 'ramipril' in gn or 'altace' in bn:
                has_ramipril = True
                if '10' in dosage:
                    ramipril_dose_ok = True

result = {
    "patient_no": patient_no,
    "patient_fname": "Jean-Pierre",
    "patient_lname": "Bouchard",
    "initial_allergy_count": initial_allergies,
    "current_active_allergies": current_active_allergies,
    "new_allergy_count": current_active_allergies - initial_allergies,
    "allergy_list": allergy_list[:10],
    "has_penicillin_allergy": has_penicillin,
    "penicillin_severity_severe": penicillin_severe,
    "has_sulfa_allergy": has_sulfa,
    "initial_drug_count": initial_drugs,
    "current_active_drugs": current_active_drugs,
    "new_drug_count": current_active_drugs - initial_drugs,
    "drug_list": drug_list[:10],
    "has_metformin": has_metformin,
    "metformin_dose_500mg": metformin_dose_ok,
    "has_ramipril": has_ramipril,
    "ramipril_dose_10mg": ramipril_dose_ok,
    "export_timestamp": __import__('datetime').datetime.now().isoformat()
}

with open('/tmp/complete_patient_profile_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export: {current_active_allergies} allergies (penicillin={has_penicillin}, sulfa={has_sulfa})")
print(f"        {current_active_drugs} drugs (metformin={has_metformin}, ramipril={has_ramipril})")
PYEOF

echo "Result saved to /tmp/complete_patient_profile_result.json"
echo "=== Export Complete ==="
