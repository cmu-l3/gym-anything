#!/bin/bash
# Export script for Lab Investigation Workflow Task
echo "=== Exporting Lab Investigation Workflow Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

PATIENT_UUID=$(cat /tmp/liw_patient_uuid 2>/dev/null || echo "")
PATIENT_IDENTIFIER=$(cat /tmp/liw_patient_identifier 2>/dev/null || echo "UNKNOWN")
BASELINE_ENCOUNTERS=$(cat /tmp/liw_initial_encounter_count 2>/dev/null || echo "0")
BASELINE_ORDERS=$(cat /tmp/liw_initial_order_count 2>/dev/null || echo "0")
BASELINE_OBS=$(cat /tmp/liw_initial_obs_count 2>/dev/null || echo "0")

if [ -z "$PATIENT_UUID" ]; then
    cat > /tmp/lab_investigation_workflow_result.json << 'EOF'
{"error": "Patient UUID not found", "patient_identifier": "UNKNOWN"}
EOF
    echo "=== Export Complete ==="
    exit 0
fi

# Query all encounters
echo "[EXPORT] Querying encounters..."
ENCOUNTERS_JSON=$(openmrs_api_get "/encounter?patient=${PATIENT_UUID}&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$ENCOUNTERS_JSON" > /tmp/liw_encounters_raw.json

# Query all orders (including test/lab orders)
echo "[EXPORT] Querying all orders..."
ALL_ORDERS_JSON=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$ALL_ORDERS_JSON" > /tmp/liw_all_orders_raw.json

# Query drug orders specifically
DRUG_ORDERS_JSON=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=drugorder&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$DRUG_ORDERS_JSON" > /tmp/liw_drug_orders_raw.json

# Query test/lab orders
TEST_ORDERS_JSON=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=testorder&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$TEST_ORDERS_JSON" > /tmp/liw_test_orders_raw.json

# Query all observations
echo "[EXPORT] Querying observations..."
OBS_JSON=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$OBS_JSON" > /tmp/liw_obs_raw.json

# MySQL query for lab results
echo "[EXPORT] Querying lab results from database..."
LAB_OBS=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT cn.name as concept_name, o.value_numeric, o.value_text, o.value_coded,
       o.date_created, et.name as encounter_type
FROM obs o
JOIN concept_name cn ON o.concept_id = cn.concept_id
JOIN encounter e ON o.encounter_id = e.encounter_id
JOIN encounter_type et ON e.encounter_type = et.encounter_type_id
WHERE o.person_id = (SELECT patient_id FROM patient_identifier WHERE identifier='${PATIENT_IDENTIFIER}' LIMIT 1)
AND cn.concept_name_type = 'FULLY_SPECIFIED'
AND cn.locale = 'en'
AND o.voided = 0
ORDER BY o.date_created DESC
LIMIT 50;
" 2>/dev/null || echo "")
echo "$LAB_OBS" > /tmp/liw_lab_obs_raw.txt

# MySQL query for all orders with concept names
ALL_ORDERS_DB=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT o.order_id, cn.name as concept_name, o.order_type_id, ot.name as order_type,
       d.name as drug_name, o.voided, o.date_created
FROM orders o
JOIN concept_name cn ON o.concept_id = cn.concept_id AND cn.concept_name_type='FULLY_SPECIFIED' AND cn.locale='en'
LEFT JOIN drug d ON o.drug_inventory_id = d.drug_id
JOIN order_type ot ON o.order_type_id = ot.order_type_id
WHERE o.patient_id = (SELECT patient_id FROM patient_identifier WHERE identifier='${PATIENT_IDENTIFIER}' LIMIT 1)
AND o.voided = 0
ORDER BY o.date_created DESC
LIMIT 30;
" 2>/dev/null || echo "")
echo "$ALL_ORDERS_DB" > /tmp/liw_all_orders_db.txt

# MySQL query for diagnoses
DIAGNOSES_DB=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT cn.name, ed.certainty, ed.date_created
FROM encounter_diagnosis ed
JOIN concept_name cn ON ed.diagnosis_coded = cn.concept_id
WHERE ed.patient_id = (SELECT patient_id FROM patient_identifier WHERE identifier='${PATIENT_IDENTIFIER}' LIMIT 1)
AND cn.locale='en' AND cn.concept_name_type='FULLY_SPECIFIED'
ORDER BY ed.date_created DESC
LIMIT 10;
" 2>/dev/null || echo "")
echo "$DIAGNOSES_DB" > /tmp/liw_diagnoses_raw.txt

python3 << 'PYEOF'
import json
import os

patient_identifier = open('/tmp/liw_patient_identifier').read().strip()
baseline_encounters = int(open('/tmp/liw_initial_encounter_count').read().strip() or '0')
baseline_orders = int(open('/tmp/liw_initial_order_count').read().strip() or '0')
baseline_obs = int(open('/tmp/liw_initial_obs_count').read().strip() or '0')

# Load all data
try:
    encounters = json.load(open('/tmp/liw_encounters_raw.json')).get('results', [])
except:
    encounters = []

try:
    all_obs = json.load(open('/tmp/liw_obs_raw.json')).get('results', [])
except:
    all_obs = []

try:
    drug_orders = json.load(open('/tmp/liw_drug_orders_raw.json')).get('results', [])
except:
    drug_orders = []

try:
    test_orders = json.load(open('/tmp/liw_test_orders_raw.json')).get('results', [])
except:
    test_orders = []

try:
    all_orders_api = json.load(open('/tmp/liw_all_orders_raw.json')).get('results', [])
except:
    all_orders_api = []

try:
    lab_obs_text = open('/tmp/liw_lab_obs_raw.txt').read().strip()
    lab_obs_lines = [l for l in lab_obs_text.split('\n') if l.strip()]
except:
    lab_obs_lines = []

try:
    all_orders_db_text = open('/tmp/liw_all_orders_db.txt').read().strip()
    all_orders_db_lines = [l for l in all_orders_db_text.split('\n') if l.strip()]
except:
    all_orders_db_lines = []

try:
    diagnosis_lines = [l for l in open('/tmp/liw_diagnoses_raw.txt').read().strip().split('\n') if l.strip()]
except:
    diagnosis_lines = []

new_encounters = len(encounters) - baseline_encounters

# Criterion 1: Clinical encounter with note
has_encounter = new_encounters > 0
has_clinical_note = False
note_length = 0
for obs in all_obs:
    value = obs.get('value', '')
    if isinstance(value, str) and len(value) >= 50:
        has_clinical_note = True
        note_length = max(note_length, len(value))

# Also check encounter obs within encounters
for enc in encounters:
    for obs in enc.get('obs', []):
        value = obs.get('value', '')
        if isinstance(value, str) and len(value) >= 50:
            has_clinical_note = True
            note_length = max(note_length, len(value))

# Criterion 2: Lab orders (CBC + malaria test)
cbc_keywords = ['cbc', 'full blood count', 'complete blood count', 'haemoglobin', 'hemoglobin',
                'wbc', 'white blood', 'white cell', 'blood count', 'fbc']
malaria_keywords = ['malaria', 'rdt', 'rapid diagnostic', 'blood film', 'thick blood', 'thin blood',
                    'plasmodium', 'malaria smear', 'parasite']

has_cbc_order = False
has_malaria_order = False
lab_order_names = []

# Check from API test orders
for order in test_orders:
    concept = order.get('concept', {}) or {}
    name = (concept.get('display', '') or concept.get('name', '') or '').lower()
    lab_order_names.append(name)
    if any(k in name for k in cbc_keywords):
        has_cbc_order = True
    if any(k in name for k in malaria_keywords):
        has_malaria_order = True

# Also check all orders
for order in all_orders_api:
    concept = order.get('concept', {}) or {}
    name = (concept.get('display', '') or concept.get('name', '') or '').lower()
    if name not in lab_order_names:
        lab_order_names.append(name)
    if any(k in name for k in cbc_keywords):
        has_cbc_order = True
    if any(k in name for k in malaria_keywords):
        has_malaria_order = True

# Check from DB orders
for line in all_orders_db_lines:
    parts = line.split('\t')
    if len(parts) >= 3:
        concept_name = parts[1].lower()
        if any(k in concept_name for k in cbc_keywords):
            has_cbc_order = True
        if any(k in concept_name for k in malaria_keywords):
            has_malaria_order = True

# Criterion 3: Lab results entered
has_cbc_results = False
has_malaria_positive = False
cbc_result_keywords = ['hemoglobin', 'haemoglobin', 'white blood', 'wbc', 'platelet', 'red blood',
                       'hematocrit', 'haematocrit', 'neutrophil', 'lymphocyte', 'monocyte']

# Check observations
all_obs_text = ' '.join(lab_obs_lines).lower()
obs_names_found = []

for obs in all_obs:
    concept = obs.get('concept', {}) or {}
    concept_name = (concept.get('display', '') or concept.get('name', '') or '').lower()
    value = obs.get('value')

    if any(k in concept_name for k in cbc_result_keywords):
        has_cbc_results = True
    if any(k in concept_name for k in malaria_keywords):
        # Check if result is positive
        value_str = str(value).lower() if value else ''
        if 'positive' in value_str or 'pos' in value_str or '1' == value_str or 'true' == value_str:
            has_malaria_positive = True
        # Also check the coded value
        if isinstance(value, dict):
            coded_name = (value.get('display', '') or value.get('name', '') or '').lower()
            if 'positive' in coded_name or 'present' in coded_name:
                has_malaria_positive = True
    obs_names_found.append(concept_name[:50])

# Check from MySQL lab obs
for line in lab_obs_lines:
    parts = line.split('\t')
    if len(parts) >= 3:
        concept_name = parts[0].lower()
        value_numeric = parts[1].strip()
        value_text = parts[2].lower().strip() if len(parts) > 2 else ''

        if any(k in concept_name for k in cbc_result_keywords):
            has_cbc_results = True
        if any(k in concept_name for k in malaria_keywords):
            if 'positive' in value_text or 'present' in value_text or (value_numeric and value_numeric not in ('0', 'NULL', '')):
                has_malaria_positive = True

# Criterion 4: Antimalarial treatment prescribed
antimalarial_keywords = ['artemether', 'lumefantrine', 'artesunate', 'quinine', 'coartem',
                         'artequin', 'fansidar', 'mefloquine', 'chloroquine', 'primaquine',
                         'artemisinin', 'artecomboo', 'dha', 'piperaquine', 'amodiaquine']

has_antimalarial = False
drug_names_found = []

for order in drug_orders:
    drug = order.get('drug', {}) or {}
    drug_name = (drug.get('name', '') or drug.get('display', '') or '').lower()
    concept = order.get('concept', {}) or {}
    concept_name = (concept.get('display', '') or '').lower()
    combined = drug_name + ' ' + concept_name
    drug_names_found.append(combined.strip())
    if any(k in combined for k in antimalarial_keywords):
        has_antimalarial = True

# Check from DB orders
for line in all_orders_db_lines:
    parts = line.split('\t')
    if len(parts) >= 5:
        concept_name = parts[1].lower()
        drug_name = parts[4].lower() if parts[4].strip() != 'NULL' else ''
        combined = concept_name + ' ' + drug_name
        if any(k in combined for k in antimalarial_keywords):
            has_antimalarial = True
            drug_names_found.append(combined.strip())

# Also check diagnoses for malaria confirmation
malaria_diagnosed = any(any(k in line.lower() for k in ['malaria', 'plasmodium']) for line in diagnosis_lines)

result = {
    "patient_identifier": patient_identifier,
    "patient_uuid": open('/tmp/liw_patient_uuid').read().strip(),
    "new_encounters": new_encounters,
    "has_encounter": has_encounter,
    "has_clinical_note": has_clinical_note,
    "note_length": note_length,
    "lab_orders": {
        "has_cbc_order": has_cbc_order,
        "has_malaria_order": has_malaria_order,
        "order_names": lab_order_names[:8]
    },
    "lab_results": {
        "has_cbc_results": has_cbc_results,
        "has_malaria_positive": has_malaria_positive,
        "obs_names": obs_names_found[:10]
    },
    "treatment": {
        "has_antimalarial": has_antimalarial,
        "drug_names": drug_names_found[:5],
        "malaria_diagnosed": malaria_diagnosed
    }
}

with open('/tmp/lab_investigation_workflow_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"[EXPORT] Encounter + note: {has_encounter}/{has_clinical_note}")
print(f"[EXPORT] Lab orders (CBC/malaria): {has_cbc_order}/{has_malaria_order}")
print(f"[EXPORT] Lab results (CBC/malaria+): {has_cbc_results}/{has_malaria_positive}")
print(f"[EXPORT] Antimalarial prescribed: {has_antimalarial}")
PYEOF

echo "[EXPORT] Result saved to /tmp/lab_investigation_workflow_result.json"
cat /tmp/lab_investigation_workflow_result.json | python3 -m json.tool > /dev/null 2>&1 && echo "[EXPORT] JSON valid"

echo "=== Export Complete ==="
