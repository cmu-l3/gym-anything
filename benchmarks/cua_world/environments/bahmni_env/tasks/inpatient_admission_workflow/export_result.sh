#!/bin/bash
# Export script for Inpatient Admission Workflow Task
echo "=== Exporting Inpatient Admission Workflow Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

PATIENT_UUID=$(cat /tmp/iaw_patient_uuid 2>/dev/null || echo "")
PATIENT_IDENTIFIER=$(cat /tmp/iaw_patient_identifier 2>/dev/null || echo "UNKNOWN")
BASELINE_ENCOUNTERS=$(cat /tmp/iaw_initial_encounter_count 2>/dev/null || echo "0")
BASELINE_ORDERS=$(cat /tmp/iaw_initial_order_count 2>/dev/null || echo "0")
BASELINE_OBS=$(cat /tmp/iaw_initial_obs_count 2>/dev/null || echo "0")

if [ -z "$PATIENT_UUID" ]; then
    cat > /tmp/inpatient_admission_workflow_result.json << 'EOF'
{"error": "Patient UUID not found", "patient_identifier": "UNKNOWN"}
EOF
    echo "=== Export Complete ==="
    exit 0
fi

# Query all encounters with type info
echo "[EXPORT] Querying encounters..."
ENCOUNTERS_JSON=$(openmrs_api_get "/encounter?patient=${PATIENT_UUID}&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$ENCOUNTERS_JSON" > /tmp/iaw_encounters_raw.json

# Query encounter types
echo "[EXPORT] Querying encounter types..."
ENCOUNTER_TYPES_JSON=$(openmrs_api_get "/encountertype?v=default" 2>/dev/null || echo '{"results":[]}')
echo "$ENCOUNTER_TYPES_JSON" > /tmp/iaw_encounter_types_raw.json

# Query all observations
echo "[EXPORT] Querying observations..."
OBS_JSON=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$OBS_JSON" > /tmp/iaw_obs_raw.json

# Query drug orders
echo "[EXPORT] Querying drug orders..."
ORDERS_JSON=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=drugorder&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$ORDERS_JSON" > /tmp/iaw_orders_raw.json

# MySQL query for diagnoses
echo "[EXPORT] Querying diagnoses..."
DIAGNOSIS_ROWS=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT ed.certainty, cn.name, ed.date_created, et.name as encounter_type
FROM encounter_diagnosis ed
JOIN concept_name cn ON ed.diagnosis_coded = cn.concept_id
JOIN encounter e ON ed.encounter_id = e.encounter_id
JOIN encounter_type et ON e.encounter_type = et.encounter_type_id
WHERE ed.patient_id = (SELECT patient_id FROM patient_identifier WHERE identifier='${PATIENT_IDENTIFIER}' LIMIT 1)
AND cn.locale='en' AND cn.concept_name_type='FULLY_SPECIFIED'
ORDER BY ed.date_created DESC
LIMIT 20;
" 2>/dev/null || echo "")
echo "$DIAGNOSIS_ROWS" > /tmp/iaw_diagnoses_raw.txt

# MySQL query for encounter types used
ENCOUNTER_TYPE_ROWS=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT e.encounter_id, et.name as type_name, e.date_created
FROM encounter e
JOIN encounter_type et ON e.encounter_type = et.encounter_type_id
WHERE e.patient_id = (SELECT patient_id FROM patient_identifier WHERE identifier='${PATIENT_IDENTIFIER}' LIMIT 1)
ORDER BY e.date_created DESC
LIMIT 10;
" 2>/dev/null || echo "")
echo "$ENCOUNTER_TYPE_ROWS" > /tmp/iaw_encounter_types_used.txt

python3 << 'PYEOF'
import json
import os

patient_identifier = open('/tmp/iaw_patient_identifier').read().strip()
baseline_encounters = int(open('/tmp/iaw_initial_encounter_count').read().strip() or '0')
baseline_orders = int(open('/tmp/iaw_initial_order_count').read().strip() or '0')
baseline_obs = int(open('/tmp/iaw_initial_obs_count').read().strip() or '0')

# Load data
try:
    with open('/tmp/iaw_encounters_raw.json') as f:
        encounters = json.load(f).get('results', [])
except:
    encounters = []

try:
    with open('/tmp/iaw_obs_raw.json') as f:
        all_obs = json.load(f).get('results', [])
except:
    all_obs = []

try:
    with open('/tmp/iaw_orders_raw.json') as f:
        all_orders = json.load(f).get('results', [])
except:
    all_orders = []

try:
    diagnosis_lines = [l for l in open('/tmp/iaw_diagnoses_raw.txt').read().strip().split('\n') if l.strip()]
except:
    diagnosis_lines = []

try:
    encounter_type_lines = [l for l in open('/tmp/iaw_encounter_types_used.txt').read().strip().split('\n') if l.strip()]
except:
    encounter_type_lines = []

# Check for inpatient encounter type
inpatient_keywords = ['inpatient', 'ipd', 'admission', 'emergency', 'ward', 'admitted', 'hospitalization']
has_inpatient_encounter = False
encounter_types_found = []

for enc in encounters:
    enc_type = enc.get('encounterType', {}) or {}
    type_name = (enc_type.get('name', '') or enc_type.get('display', '') or '').lower()
    encounter_types_found.append(type_name)
    if any(kw in type_name for kw in inpatient_keywords):
        has_inpatient_encounter = True

# Also check MySQL encounter type rows
enc_type_text = ' '.join(encounter_type_lines).lower()
if any(kw in enc_type_text for kw in inpatient_keywords):
    has_inpatient_encounter = True
for line in encounter_type_lines:
    parts = line.split('\t')
    if len(parts) >= 2:
        type_name = parts[1].lower()
        if type_name not in encounter_types_found:
            encounter_types_found.append(type_name)

new_encounters = len(encounters) - baseline_encounters

# Check vitals - respiratory and fever focused
TEMP_UUID = '5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
RR_UUID = '5242AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
SPO2_UUID = '5092AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
SYSTOLIC_UUID = '5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
DIASTOLIC_UUID = '5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
PULSE_UUID = '5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'

has_temp = False
has_rr = False
has_spo2 = False
has_bp = False
vital_values = {}

for obs in all_obs:
    cuuid = obs.get('concept', {}).get('uuid', '')
    val = obs.get('value')
    if cuuid == TEMP_UUID:
        has_temp = True
        vital_values['temperature'] = val
    elif cuuid == RR_UUID:
        has_rr = True
        vital_values['respiratory_rate'] = val
    elif cuuid == SPO2_UUID:
        has_spo2 = True
        vital_values['spo2'] = val
    elif cuuid == SYSTOLIC_UUID:
        has_bp = True
        vital_values['systolic_bp'] = val
    elif cuuid == DIASTOLIC_UUID:
        vital_values['diastolic_bp'] = val
    elif cuuid == PULSE_UUID:
        vital_values['pulse'] = val

vital_count = sum([has_temp, has_rr, has_spo2, has_bp])
vitals_adequate = vital_count >= 3  # At least 3 of the 4 types

# Check diagnoses
diagnosis_lower = ' '.join(diagnosis_lines).lower()
has_pneumonia_dx = any(term in diagnosis_lower for term in [
    'pneumonia', 'community-acquired', 'cap', 'respiratory infection', 'lung infection',
    'bronchopneumonia', 'lobar pneumonia', 'atypical pneumonia'
])
has_additional_dx = len(diagnosis_lines) >= 2

# Check second relevant diagnosis
has_relevant_second_dx = any(term in diagnosis_lower for term in [
    'fever', 'pyrexia', 'respiratory failure', 'respiratory distress', 'sepsis',
    'dyspnea', 'dyspnoea', 'pleuritis', 'pleural effusion', 'hypoxia', 'cough',
    'infection', 'malaria', 'typhoid', 'tuberculosis', 'tb'
])

two_diagnoses = has_pneumonia_dx and (has_additional_dx or has_relevant_second_dx)

# Check drug orders (at least 2 for inpatient)
new_orders = len(all_orders) - baseline_orders
drug_names = []
for order in all_orders:
    drug = order.get('drug', {}) or {}
    name = (drug.get('name', '') or drug.get('display', '') or
            order.get('concept', {}).get('display', '') or '').lower()
    if name:
        drug_names.append(name)

has_two_medications = len(all_orders) >= 2

# Check for pneumonia-relevant antibiotics
pneumonia_antibiotics = ['amoxicillin', 'amoxycillin', 'ampicillin', 'penicillin', 'ceftriaxone',
                         'azithromycin', 'erythromycin', 'doxycycline', 'cotrimoxazole',
                         'ciprofloxacin', 'levofloxacin', 'clarithromycin', 'benzylpenicillin',
                         'procaine penicillin', 'chloramphenicol', 'cefuroxime']
has_antibiotic = any(any(ab in name for ab in pneumonia_antibiotics) for name in drug_names)

# Check clinical note
has_admission_note = False
note_length = 0
for obs in all_obs:
    value = obs.get('value', '')
    if isinstance(value, str) and len(value) >= 150:
        has_admission_note = True
        note_length = max(note_length, len(value))

result = {
    "patient_identifier": patient_identifier,
    "patient_uuid": open('/tmp/iaw_patient_uuid').read().strip(),
    "new_encounters": new_encounters,
    "encounter_types_found": encounter_types_found[:5],
    "has_inpatient_encounter": has_inpatient_encounter,
    "vitals": {
        "has_temp": has_temp,
        "has_rr": has_rr,
        "has_spo2": has_spo2,
        "has_bp": has_bp,
        "vital_count": vital_count,
        "vitals_adequate": vitals_adequate,
        "vital_values": vital_values
    },
    "diagnoses": {
        "has_pneumonia_dx": has_pneumonia_dx,
        "two_diagnoses": two_diagnoses,
        "diagnosis_lines": diagnosis_lines[:10]
    },
    "medications": {
        "total_orders": len(all_orders),
        "new_orders": new_orders,
        "has_two_medications": has_two_medications,
        "has_antibiotic": has_antibiotic,
        "drug_names": drug_names[:8]
    },
    "admission_note": {
        "has_admission_note": has_admission_note,
        "note_length": note_length
    }
}

with open('/tmp/inpatient_admission_workflow_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"[EXPORT] Inpatient encounter: {has_inpatient_encounter}")
print(f"[EXPORT] Vitals adequate: {vitals_adequate} ({vital_count}/4)")
print(f"[EXPORT] Two diagnoses (pneumonia+): {two_diagnoses}")
print(f"[EXPORT] Two medications: {has_two_medications}")
print(f"[EXPORT] Admission note: {has_admission_note}")
PYEOF

echo "[EXPORT] Result saved to /tmp/inpatient_admission_workflow_result.json"
cat /tmp/inpatient_admission_workflow_result.json | python3 -m json.tool > /dev/null 2>&1 && echo "[EXPORT] JSON valid"

echo "=== Export Complete ==="
