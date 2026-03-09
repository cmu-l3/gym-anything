#!/bin/bash
# Export script for Medication Review and Allergy task in OSCAR EMR

echo "=== Exporting Medication Review and Allergy Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

PATIENT_NO=$(cat /tmp/task_patient_no_medreview 2>/dev/null || oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Fatima' AND last_name='Al-Hassan' LIMIT 1")
INITIAL_DRUG_COUNT=$(cat /tmp/initial_drug_count_medreview 2>/dev/null || echo "1")
INITIAL_ALLERGY_COUNT=$(cat /tmp/initial_allergy_count_medreview 2>/dev/null || echo "0")

echo "Patient demographic_no: $PATIENT_NO"

python3 << PYEOF
import json, subprocess

patient_no = "${PATIENT_NO}"
initial_drugs = int("${INITIAL_DRUG_COUNT}".strip() or "1")
initial_allergies = int("${INITIAL_ALLERGY_COUNT}".strip() or "0")

def run_query(q):
    try:
        r = subprocess.run(
            ['docker', 'exec', 'oscar-db', 'mysql', '-u', 'oscar', '-poscar', 'oscar', '-N', '-e', q],
            capture_output=True, text=True, timeout=15
        )
        return r.stdout.strip()
    except Exception:
        return ""

# Check Amiodarone status
amiodarone_row = run_query(f"SELECT drugid, GN, archived FROM drugs WHERE demographic_no={patient_no} AND GN LIKE '%Amiodarone%' ORDER BY drugid DESC LIMIT 1")
# Check Metformin (active)
metformin_row = run_query(f"SELECT drugid, GN, dosage, freqcode, archived FROM drugs WHERE demographic_no={patient_no} AND (GN LIKE '%Metformin%' OR BN LIKE '%Glucophage%') ORDER BY drugid DESC LIMIT 1")
# Check all active drugs
active_drugs_rows = run_query(f"SELECT GN, BN, dosage, archived FROM drugs WHERE demographic_no={patient_no} ORDER BY drugid DESC")
# Check ASA allergy
asa_row = run_query(f"SELECT ALLERGY_ID, DESCRIPTION, reaction, severity_of_reaction, archived FROM allergies WHERE demographic_no={patient_no} AND (DESCRIPTION LIKE '%ASA%' OR DESCRIPTION LIKE '%Acetylsalicylic%' OR DESCRIPTION LIKE '%aspirin%') ORDER BY ALLERGY_ID DESC LIMIT 1")
# All allergies
all_allergies_rows = run_query(f"SELECT DESCRIPTION, reaction, severity_of_reaction, archived FROM allergies WHERE demographic_no={patient_no} ORDER BY ALLERGY_ID DESC")
current_active_allergies = int(run_query(f"SELECT COUNT(*) FROM allergies WHERE demographic_no={patient_no} AND archived=0") or "0")
current_active_drugs = int(run_query(f"SELECT COUNT(*) FROM drugs WHERE demographic_no={patient_no} AND archived=0") or "0")

# Parse Amiodarone status
amiodarone_archived = None
amiodarone_found = False
if amiodarone_row:
    parts = amiodarone_row.split('\t')
    amiodarone_found = True
    amiodarone_archived = parts[2].strip() if len(parts) > 2 else '0'
    amiodarone_archived = amiodarone_archived == '1'

# Parse Metformin status
metformin_found = False
metformin_active = False
metformin_dose_ok = False
if metformin_row:
    parts = metformin_row.split('\t')
    metformin_found = True
    dosage = parts[2].strip() if len(parts) > 2 else ''
    archived = parts[4].strip() if len(parts) > 4 else '1'
    metformin_active = archived == '0'
    metformin_dose_ok = '500' in dosage

# Parse ASA allergy
asa_allergy_found = False
asa_allergy_active = False
asa_severity_moderate = False
if asa_row:
    parts = asa_row.split('\t')
    asa_allergy_found = True
    archived = parts[4].strip() if len(parts) > 4 else '1'
    asa_allergy_active = archived == '0'
    severity = parts[3].strip().lower() if len(parts) > 3 else ''
    asa_severity_moderate = severity in ('mo', 'moderate') or 'moderate' in severity

# Parse all drugs for summary
drug_summary = []
for line in active_drugs_rows.splitlines():
    parts = line.split('\t')
    if len(parts) >= 3:
        drug_summary.append({'gn': parts[0], 'dosage': parts[2] if len(parts)>2 else '', 'archived': parts[3] if len(parts)>3 else '?'})

# Parse all allergies for summary
allergy_summary = []
for line in all_allergies_rows.splitlines():
    parts = line.split('\t')
    if len(parts) >= 1:
        allergy_summary.append({'desc': parts[0], 'severity': parts[2] if len(parts)>2 else '', 'archived': parts[3] if len(parts)>3 else '?'})

result = {
    "patient_no": patient_no,
    "patient_fname": "Fatima",
    "patient_lname": "Al-Hassan",
    "initial_drug_count": initial_drugs,
    "current_active_drugs": current_active_drugs,
    "amiodarone_found_in_db": amiodarone_found,
    "amiodarone_archived": amiodarone_archived,
    "metformin_found": metformin_found,
    "metformin_active": metformin_active,
    "metformin_dose_500mg": metformin_dose_ok,
    "initial_allergy_count": initial_allergies,
    "current_active_allergies": current_active_allergies,
    "asa_allergy_found": asa_allergy_found,
    "asa_allergy_active": asa_allergy_active,
    "asa_severity_moderate": asa_severity_moderate,
    "drug_summary": drug_summary[:10],
    "allergy_summary": allergy_summary[:10],
    "export_timestamp": __import__('datetime').datetime.now().isoformat()
}

with open('/tmp/medication_review_and_allergy_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export: Amiodarone found={amiodarone_found}, archived={amiodarone_archived}")
print(f"        Metformin found={metformin_found}, active={metformin_active}")
print(f"        ASA allergy found={asa_allergy_found}, active={asa_allergy_active}")
PYEOF

echo "Result saved to /tmp/medication_review_and_allergy_result.json"
echo "=== Export Complete ==="
