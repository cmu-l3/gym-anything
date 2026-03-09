#!/bin/bash
# Export script for Chronic Disease Follow-up Task
echo "=== Exporting Chronic Disease Follow-up Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Read stored patient info
PATIENT_UUID=$(cat /tmp/cdfu_patient_uuid 2>/dev/null || echo "")
PATIENT_IDENTIFIER=$(cat /tmp/cdfu_patient_identifier 2>/dev/null || echo "UNKNOWN")
BASELINE_ENCOUNTERS=$(cat /tmp/cdfu_initial_encounter_count 2>/dev/null || echo "0")
BASELINE_ORDERS=$(cat /tmp/cdfu_initial_order_count 2>/dev/null || echo "0")
BASELINE_OBS=$(cat /tmp/cdfu_initial_obs_count 2>/dev/null || echo "0")
START_TIME=$(cat /tmp/cdfu_start_time 2>/dev/null || echo "")

if [ -z "$PATIENT_UUID" ]; then
    echo "[ERROR] Patient UUID not found - setup may have failed"
    cat > /tmp/chronic_disease_followup_result.json << 'EOF'
{
    "error": "Patient UUID not found",
    "patient_identifier": "UNKNOWN",
    "passed_wrong_target_gate": false
}
EOF
    echo "=== Export Complete ==="
    exit 0
fi

echo "[EXPORT] Patient UUID: ${PATIENT_UUID}"
echo "[EXPORT] Patient Identifier: ${PATIENT_IDENTIFIER}"

# Query all encounters for this patient
echo "[EXPORT] Querying encounters..."
ENCOUNTERS_JSON=$(openmrs_api_get "/encounter?patient=${PATIENT_UUID}&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$ENCOUNTERS_JSON" > /tmp/cdfu_encounters_raw.json

# Query all observations for this patient
echo "[EXPORT] Querying observations..."
OBS_JSON=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$OBS_JSON" > /tmp/cdfu_obs_raw.json

# Query drug orders for this patient
echo "[EXPORT] Querying drug orders..."
ORDERS_JSON=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=drugorder&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$ORDERS_JSON" > /tmp/cdfu_orders_raw.json

# Query MySQL for diagnoses
echo "[EXPORT] Querying diagnoses from database..."
DIAGNOSIS_ROWS=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT ed.certainty, cn.name, ed.date_created
FROM encounter_diagnosis ed
JOIN concept_name cn ON ed.diagnosis_coded = cn.concept_id
WHERE ed.patient_id = (SELECT patient_id FROM patient_identifier WHERE identifier='${PATIENT_IDENTIFIER}' LIMIT 1)
AND cn.locale='en' AND cn.concept_name_type='FULLY_SPECIFIED'
ORDER BY ed.date_created DESC
LIMIT 20;
" 2>/dev/null || echo "")
echo "$DIAGNOSIS_ROWS" > /tmp/cdfu_diagnoses_raw.txt

# Use Python to analyze and create result JSON
python3 << 'PYEOF'
import json
import os
import re

patient_identifier = open('/tmp/cdfu_patient_identifier').read().strip()
baseline_encounters = int(open('/tmp/cdfu_initial_encounter_count').read().strip() or '0')
baseline_orders = int(open('/tmp/cdfu_initial_order_count').read().strip() or '0')
baseline_obs = int(open('/tmp/cdfu_initial_obs_count').read().strip() or '0')

# Load raw data
try:
    with open('/tmp/cdfu_encounters_raw.json') as f:
        encounters_data = json.load(f)
    encounters = encounters_data.get('results', [])
except:
    encounters = []

try:
    with open('/tmp/cdfu_obs_raw.json') as f:
        obs_data = json.load(f)
    all_obs = obs_data.get('results', [])
except:
    all_obs = []

try:
    with open('/tmp/cdfu_orders_raw.json') as f:
        orders_data = json.load(f)
    all_orders = orders_data.get('results', [])
except:
    all_orders = []

try:
    diagnosis_text = open('/tmp/cdfu_diagnoses_raw.txt').read().strip()
    diagnosis_lines = [l for l in diagnosis_text.split('\n') if l.strip()]
except:
    diagnosis_lines = []

# Current encounter and order counts
current_encounter_count = len(encounters)
current_order_count = len(all_orders)
current_obs_count = len(all_obs)

new_encounters = current_encounter_count - baseline_encounters
new_orders = current_order_count - baseline_orders
new_obs = current_obs_count - baseline_obs

# CIEL concept UUIDs for vitals
SYSTOLIC_UUID = '5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
DIASTOLIC_UUID = '5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
PULSE_UUID = '5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
WEIGHT_UUID = '5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
TEMP_UUID = '5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
HEIGHT_UUID = '5090AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'

# Check vitals
has_systolic = False
has_diastolic = False
has_pulse = False
has_weight_or_temp = False
systolic_value = None
diastolic_value = None
pulse_value = None

for obs in all_obs:
    concept_uuid = obs.get('concept', {}).get('uuid', '')
    value = obs.get('value')
    if concept_uuid == SYSTOLIC_UUID:
        has_systolic = True
        systolic_value = value
    elif concept_uuid == DIASTOLIC_UUID:
        has_diastolic = True
        diastolic_value = value
    elif concept_uuid == PULSE_UUID:
        has_pulse = True
        pulse_value = value
    elif concept_uuid in (WEIGHT_UUID, TEMP_UUID, HEIGHT_UUID):
        has_weight_or_temp = True

vitals_complete = has_systolic and has_diastolic and has_pulse and has_weight_or_temp

# Check diagnoses from MySQL output
diagnosis_lower = ' '.join(diagnosis_lines).lower()
has_diabetes_dx = any(term in diagnosis_lower for term in [
    'diabetes', 'type 2', 'type ii', 't2dm', 'dm2', 'non-insulin', 'niddm',
    'diabetic', 'hyperglycaemia', 'hyperglycemia'
])
has_htn_dx = any(term in diagnosis_lower for term in [
    'hypertension', 'essential hypertension', 'htn', 'high blood pressure',
    'arterial hypertension', 'systemic hypertension'
])
two_diagnoses = has_diabetes_dx and has_htn_dx

# Check drug orders
dm_drugs = ['metformin', 'glibenclamide', 'glipizide', 'gliclazide', 'insulin',
            'sitagliptin', 'empagliflozin', 'dapagliflozin', 'pioglitazone', 'tolbutamide',
            'acarbose', 'repaglinide', 'glimepiride']
htn_drugs = ['amlodipine', 'enalapril', 'lisinopril', 'losartan', 'hydrochlorothiazide',
             'furosemide', 'atenolol', 'metoprolol', 'nifedipine', 'captopril',
             'ramipril', 'valsartan', 'candesartan', 'perindopril', 'bisoprolol',
             'propranolol', 'spironolactone', 'chlorthalidone', 'indapamide']

has_dm_drug = False
has_htn_drug = False
drug_names_found = []

for order in all_orders:
    drug = order.get('drug', {}) or {}
    drug_name = (drug.get('name', '') or drug.get('display', '') or '').lower()
    # Also check concept name
    concept = order.get('concept', {}) or {}
    concept_name = (concept.get('display', '') or concept.get('name', '') or '').lower()
    combined_name = drug_name + ' ' + concept_name

    drug_names_found.append(combined_name.strip())

    if any(d in combined_name for d in dm_drugs):
        has_dm_drug = True
    if any(d in combined_name for d in htn_drugs):
        has_htn_drug = True

two_drugs = has_dm_drug and has_htn_drug

# Check clinical note (free text obs)
NOTE_CONCEPT_UUIDS = [
    '160632AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',  # Clinical note
    '165095AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',  # Chief complaint
    '1390AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',  # History of present illness
]
has_clinical_note = False
note_length = 0

for obs in all_obs:
    concept_uuid = obs.get('concept', {}).get('uuid', '')
    value = obs.get('value', '')
    if isinstance(value, str) and len(value) >= 100:
        has_clinical_note = True
        note_length = max(note_length, len(value))
    # Also check encounter notes in encounters
for enc in encounters:
    enc_notes = enc.get('encounterProviders', [])
    # Check obs within encounters
    for obs in enc.get('obs', []):
        value = obs.get('value', '')
        if isinstance(value, str) and len(value) >= 100:
            has_clinical_note = True
            note_length = max(note_length, len(value))

result = {
    "patient_identifier": patient_identifier,
    "patient_uuid": open('/tmp/cdfu_patient_uuid').read().strip(),
    "baseline_encounter_count": baseline_encounters,
    "current_encounter_count": current_encounter_count,
    "new_encounters": new_encounters,
    "baseline_order_count": baseline_orders,
    "current_order_count": current_order_count,
    "new_orders": new_orders,
    "baseline_obs_count": baseline_obs,
    "current_obs_count": current_obs_count,
    "new_obs": new_obs,
    "vitals": {
        "has_systolic": has_systolic,
        "has_diastolic": has_diastolic,
        "has_pulse": has_pulse,
        "has_weight_or_temp": has_weight_or_temp,
        "vitals_complete": vitals_complete,
        "systolic_value": systolic_value,
        "diastolic_value": diastolic_value,
        "pulse_value": pulse_value
    },
    "diagnoses": {
        "has_diabetes_dx": has_diabetes_dx,
        "has_htn_dx": has_htn_dx,
        "two_diagnoses": two_diagnoses,
        "raw_diagnosis_lines": diagnosis_lines[:10]
    },
    "medications": {
        "has_dm_drug": has_dm_drug,
        "has_htn_drug": has_htn_drug,
        "two_drugs": two_drugs,
        "drug_names_found": drug_names_found[:10]
    },
    "clinical_note": {
        "has_clinical_note": has_clinical_note,
        "note_length": note_length
    }
}

with open('/tmp/chronic_disease_followup_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"[EXPORT] New encounters: {new_encounters}")
print(f"[EXPORT] Vitals complete: {vitals_complete}")
print(f"[EXPORT] Two diagnoses (DM+HTN): {two_diagnoses}")
print(f"[EXPORT] Two drug classes: {two_drugs}")
print(f"[EXPORT] Clinical note: {has_clinical_note}")
PYEOF

echo "[EXPORT] Result saved to /tmp/chronic_disease_followup_result.json"
cat /tmp/chronic_disease_followup_result.json | python3 -m json.tool > /dev/null 2>&1 && echo "[EXPORT] JSON valid" || echo "[WARN] JSON may be invalid"

echo "=== Export Complete ==="
