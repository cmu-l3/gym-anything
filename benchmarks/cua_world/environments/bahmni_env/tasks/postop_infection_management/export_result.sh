#!/bin/bash
echo "=== Exporting postop_infection_management results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/pim_final.png

# -------------------------------------------------------------------
# Read stored state from setup
# -------------------------------------------------------------------
PATIENT_UUID=$(cat /tmp/pim_patient_uuid 2>/dev/null || echo "")
PATIENT_ID=$(cat /tmp/pim_patient_identifier 2>/dev/null || echo "")
START_TIME=$(cat /tmp/pim_start_time 2>/dev/null || echo "")
START_TS=$(cat /tmp/pim_task_start_timestamp 2>/dev/null || echo "0")
INITIAL_ENC=$(cat /tmp/pim_initial_encounter_count 2>/dev/null || echo "0")
INITIAL_OBS=$(cat /tmp/pim_initial_obs_count 2>/dev/null || echo "0")
INITIAL_DRUG=$(cat /tmp/pim_initial_drug_order_count 2>/dev/null || echo "0")
INITIAL_TEST=$(cat /tmp/pim_initial_test_order_count 2>/dev/null || echo "0")
INITIAL_ALLERGY=$(cat /tmp/pim_initial_allergy_count 2>/dev/null || echo "0")

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: No patient UUID found"
    echo '{"error": "No patient UUID found", "patient_identifier": ""}' > /tmp/postop_infection_management_result.json
    chmod 666 /tmp/postop_infection_management_result.json 2>/dev/null || true
    exit 0
fi

# -------------------------------------------------------------------
# Query current state via REST API and MySQL
# -------------------------------------------------------------------

# All encounters
ENCOUNTERS_RAW=$(openmrs_api_get "/encounter?patient=${PATIENT_UUID}&v=full" 2>/dev/null || echo '{"results":[]}')

# All observations
OBS_RAW=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&v=full" 2>/dev/null || echo '{"results":[]}')

# Allergies — query MySQL directly since REST allergy endpoint may return 500
ALLERGIES_MYSQL=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT a.allergy_id, cn_allergen.name as allergen, cn_severity.name as severity,
       cn_reaction.name as reaction, a.non_coded_allergen
FROM allergy a
LEFT JOIN concept_name cn_allergen ON a.coded_allergen = cn_allergen.concept_id
    AND cn_allergen.concept_name_type = 'FULLY_SPECIFIED' AND cn_allergen.locale = 'en'
LEFT JOIN concept_name cn_severity ON a.severity_concept_id = cn_severity.concept_id
    AND cn_severity.concept_name_type = 'FULLY_SPECIFIED' AND cn_severity.locale = 'en'
LEFT JOIN allergy_reaction ar ON a.allergy_id = ar.allergy_id
LEFT JOIN concept_name cn_reaction ON ar.reaction_concept_id = cn_reaction.concept_id
    AND cn_reaction.concept_name_type = 'FULLY_SPECIFIED' AND cn_reaction.locale = 'en'
WHERE a.patient_id = (SELECT patient_id FROM patient_identifier WHERE identifier = '${PATIENT_ID}' LIMIT 1)
AND a.voided = 0;
" 2>/dev/null || echo "")
ALLERGIES_RAW="[]"  # REST endpoint not used; MySQL results parsed below

# Drug orders (including voided)
DRUG_ORDERS_RAW=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=drugorder&v=full" 2>/dev/null || echo '{"results":[]}')

# Test orders
TEST_ORDERS_RAW=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=testorder&v=full" 2>/dev/null || echo '{"results":[]}')

# Diagnoses via MySQL
DIAGNOSES_MYSQL=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT cn.name, ed.dx_rank, ed.certainty, e.encounter_datetime
FROM encounter_diagnosis ed
JOIN encounter e ON ed.encounter_id = e.encounter_id
JOIN concept_name cn ON ed.diagnosis_coded = cn.concept_id
    AND cn.concept_name_type = 'FULLY_SPECIFIED' AND cn.locale = 'en'
WHERE e.patient_id = (
    SELECT patient_id FROM patient_identifier WHERE identifier = '${PATIENT_ID}' LIMIT 1
)
ORDER BY e.encounter_datetime DESC;
" 2>/dev/null || echo "")

# -------------------------------------------------------------------
# Analyze results via inline Python
# -------------------------------------------------------------------
TEMP_RESULT=$(mktemp /tmp/pim_result.XXXXXX.json)

python3 << PYEOF
import json, sys
from datetime import datetime

# CIEL concept UUIDs for vital signs
VITAL_UUIDS = {
    'temperature':      '5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'pulse':            '5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'systolic_bp':      '5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'diastolic_bp':     '5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'respiratory_rate': '5242AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'spo2':             '5092AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'weight':           '5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
}

task_start_ts = int("${START_TS}" or "0")
task_start_time = "${START_TIME}"

# Parse observations
try:
    obs_data = json.loads('''${OBS_RAW}''')
    all_obs = obs_data.get('results', [])
except:
    all_obs = []

# Check vitals recorded AFTER task start
vitals_found = {}
clinical_note_text = ""
clinical_note_length = 0

for ob in all_obs:
    obs_dt = ob.get('obsDatetime', '')
    concept = ob.get('concept', {})
    concept_uuid = concept.get('uuid', '')
    concept_name = concept.get('display', '').lower()
    value = ob.get('value', '')

    # Skip observations from before task start (allow 10s grace)
    if obs_dt and task_start_time:
        try:
            obs_time = obs_dt.replace('+0000', '+00:00').replace('.000+00:00', '+00:00')
            if obs_dt < task_start_time and task_start_ts > 0:
                import time
                obs_epoch = 0
                try:
                    from datetime import timezone
                    dt = datetime.fromisoformat(obs_time)
                    obs_epoch = int(dt.timestamp())
                except:
                    pass
                if obs_epoch > 0 and obs_epoch < (task_start_ts - 10):
                    # Check if this is a text note from before task
                    if isinstance(value, str) and len(value) >= 200:
                        pass  # still skip pre-task notes
                    continue
        except:
            pass

    # Match vitals by CIEL UUID
    for vital_name, vital_uuid in VITAL_UUIDS.items():
        if concept_uuid == vital_uuid:
            vitals_found[vital_name] = value

    # Check for clinical note (free-text observation >= 200 chars)
    if isinstance(value, str) and len(value) >= 200:
        if len(value) > clinical_note_length:
            clinical_note_text = value[:500]
            clinical_note_length = len(value)

# Parse allergies from MySQL output
penicillin_allergy_found = False
allergy_details = {}
allergy_count = 0
allergy_lines = """${ALLERGIES_MYSQL}""".strip().split('\n')
for line in allergy_lines:
    if not line.strip():
        continue
    allergy_count += 1
    parts = line.split('\t')
    if len(parts) >= 2:
        allergen_name = (parts[1] or '').lower()
        severity_name = parts[2] if len(parts) > 2 else ''
        reaction_name = parts[3] if len(parts) > 3 else ''
        non_coded = parts[4] if len(parts) > 4 else ''
        if 'penicillin' in allergen_name or 'penicillin' in non_coded.lower():
            penicillin_allergy_found = True
            allergy_details = {
                'allergen': allergen_name or non_coded,
                'severity': severity_name,
                'reactions': [reaction_name] if reaction_name else []
            }

# Parse drug orders
try:
    drug_data = json.loads('''${DRUG_ORDERS_RAW}''')
    drug_orders = drug_data.get('results', [])
except:
    drug_orders = []

ciprofloxacin_prescribed = False
penicillin_class_prescribed = False
ciprofloxacin_details = {}

PENICILLIN_CLASS = ['amoxicillin', 'ampicillin', 'penicillin', 'flucloxacillin',
                    'piperacillin', 'cloxacillin', 'dicloxacillin', 'nafcillin',
                    'oxacillin', 'ticarcillin', 'mezlocillin']

for order in drug_orders:
    drug = order.get('drug', {})
    drug_name = (drug.get('display', '') or order.get('concept', {}).get('display', '')).lower()
    order_action = order.get('action', '')

    if order_action == 'DISCONTINUE':
        continue

    if 'ciprofloxacin' in drug_name:
        ciprofloxacin_prescribed = True
        ciprofloxacin_details = {
            'drug_name': drug_name,
            'dose': order.get('dose', ''),
            'frequency': order.get('frequency', {}).get('display', '') if order.get('frequency') else '',
            'duration': order.get('duration', ''),
        }

    for pen_drug in PENICILLIN_CLASS:
        if pen_drug in drug_name:
            penicillin_class_prescribed = True

# Parse test orders
try:
    test_data = json.loads('''${TEST_ORDERS_RAW}''')
    test_orders = test_data.get('results', [])
except:
    test_orders = []

cbc_ordered = False
crp_ordered = False

CBC_KEYWORDS = ['cbc', 'complete blood count', 'full blood count', 'hemogram', 'fbc',
                'blood count', 'haemogram']
CRP_KEYWORDS = ['c-reactive protein', 'crp', 'c reactive protein']

for order in test_orders:
    concept_name = order.get('concept', {}).get('display', '').lower()
    for kw in CBC_KEYWORDS:
        if kw in concept_name:
            cbc_ordered = True
    for kw in CRP_KEYWORDS:
        if kw in concept_name:
            crp_ordered = True

# Parse diagnoses from MySQL
diagnoses_lines = """${DIAGNOSES_MYSQL}""".strip().split('\n')
appendicitis_found = False
wound_infection_found = False

APPENDICITIS_KEYWORDS = ['appendicitis', 'appendiceal', 'appendicular']
WOUND_KEYWORDS = ['wound infection', 'surgical site infection', 'ssi',
                  'wound sepsis', 'post-operative infection', 'postoperative infection',
                  'post operative infection']

for line in diagnoses_lines:
    line_lower = line.strip().lower()
    for kw in APPENDICITIS_KEYWORDS:
        if kw in line_lower:
            appendicitis_found = True
    for kw in WOUND_KEYWORDS:
        if kw in line_lower:
            wound_infection_found = True

# Count new data (for anti-gaming)
current_enc_count = len(json.loads('''${ENCOUNTERS_RAW}''').get('results', [])) if '''${ENCOUNTERS_RAW}''' else 0
new_encounters = current_enc_count - int("${INITIAL_ENC}" or "0")

# Build result
result = {
    'patient_uuid': '${PATIENT_UUID}',
    'patient_identifier': '${PATIENT_ID}',
    'task_start_time': task_start_time,
    'task_start_timestamp': task_start_ts,
    'new_encounters_created': new_encounters,
    'vitals': {
        'found': vitals_found,
        'count': len(vitals_found),
        'has_temperature': 'temperature' in vitals_found,
        'has_pulse': 'pulse' in vitals_found,
        'has_systolic': 'systolic_bp' in vitals_found,
        'has_diastolic': 'diastolic_bp' in vitals_found,
        'has_rr': 'respiratory_rate' in vitals_found,
        'has_spo2': 'spo2' in vitals_found,
        'has_weight': 'weight' in vitals_found,
    },
    'allergy': {
        'penicillin_documented': penicillin_allergy_found,
        'details': allergy_details,
        'total_allergies': allergy_count,
    },
    'medications': {
        'ciprofloxacin_prescribed': ciprofloxacin_prescribed,
        'ciprofloxacin_details': ciprofloxacin_details,
        'penicillin_class_prescribed': penicillin_class_prescribed,
        'total_drug_orders': len(drug_orders),
    },
    'investigations': {
        'cbc_ordered': cbc_ordered,
        'crp_ordered': crp_ordered,
        'total_test_orders': len(test_orders),
    },
    'diagnoses': {
        'appendicitis_found': appendicitis_found,
        'wound_infection_found': wound_infection_found,
        'raw_mysql': """${DIAGNOSES_MYSQL}""".strip()[:1000],
    },
    'clinical_note': {
        'found': clinical_note_length >= 200,
        'length': clinical_note_length,
        'excerpt': clinical_note_text[:200] if clinical_note_text else '',
    },
}

with open('${TEMP_RESULT}', 'w') as f:
    json.dump(result, f, indent=2, default=str)

print("Result written successfully")
PYEOF

# -------------------------------------------------------------------
# Write final result with safe permissions
# -------------------------------------------------------------------
rm -f /tmp/postop_infection_management_result.json 2>/dev/null || sudo rm -f /tmp/postop_infection_management_result.json 2>/dev/null || true
cp "$TEMP_RESULT" /tmp/postop_infection_management_result.json 2>/dev/null || sudo cp "$TEMP_RESULT" /tmp/postop_infection_management_result.json
chmod 666 /tmp/postop_infection_management_result.json 2>/dev/null || sudo chmod 666 /tmp/postop_infection_management_result.json 2>/dev/null || true
rm -f "$TEMP_RESULT"

echo "=== Export complete ==="
