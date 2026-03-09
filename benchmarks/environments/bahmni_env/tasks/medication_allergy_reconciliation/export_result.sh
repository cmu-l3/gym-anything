#!/bin/bash
# Export script for Medication Allergy Reconciliation Task
echo "=== Exporting Medication Allergy Reconciliation Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

PATIENT_UUID=$(cat /tmp/mar_patient_uuid 2>/dev/null || echo "")
PATIENT_IDENTIFIER=$(cat /tmp/mar_patient_identifier 2>/dev/null || echo "UNKNOWN")
BASELINE_ORDERS=$(cat /tmp/mar_initial_order_count 2>/dev/null || echo "0")
BASELINE_ALLERGIES=$(cat /tmp/mar_initial_allergy_count 2>/dev/null || echo "0")
START_TIME=$(cat /tmp/mar_start_time 2>/dev/null || echo "")

if [ -z "$PATIENT_UUID" ]; then
    cat > /tmp/medication_allergy_reconciliation_result.json << 'EOF'
{"error": "Patient UUID not found", "patient_identifier": "UNKNOWN"}
EOF
    echo "=== Export Complete ==="
    exit 0
fi

# Query current allergy list
echo "[EXPORT] Querying allergy list..."
ALLERGIES_JSON=$(openmrs_api_get "/patient/${PATIENT_UUID}/allergy?v=full" 2>/dev/null || echo '{"results":[]}')
echo "$ALLERGIES_JSON" > /tmp/mar_allergies_raw.json

# Query all drug orders (including voided)
echo "[EXPORT] Querying all drug orders..."
ORDERS_JSON=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=drugorder&includeVoided=true&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$ORDERS_JSON" > /tmp/mar_orders_raw.json

# Query observations for clinical notes
echo "[EXPORT] Querying observations..."
OBS_JSON=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$OBS_JSON" > /tmp/mar_obs_raw.json

# MySQL query for order status and voided orders
echo "[EXPORT] Querying order status from database..."
ORDER_STATUS=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT o.order_id, cn.name as drug_name, o.voided, o.date_stopped, o.order_action
FROM orders o
JOIN concept_name cn ON o.concept_id = cn.concept_id
WHERE o.patient_id = (SELECT patient_id FROM patient_identifier WHERE identifier='${PATIENT_IDENTIFIER}' LIMIT 1)
AND cn.concept_name_type = 'FULLY_SPECIFIED'
AND cn.locale = 'en'
ORDER BY o.date_created DESC
LIMIT 30;
" 2>/dev/null || echo "")
echo "$ORDER_STATUS" > /tmp/mar_order_status_raw.txt

python3 << 'PYEOF'
import json
import os

patient_identifier = open('/tmp/mar_patient_identifier').read().strip()
baseline_orders = int(open('/tmp/mar_initial_order_count').read().strip() or '0')
baseline_allergies = int(open('/tmp/mar_initial_allergy_count').read().strip() or '0')

# Load allergies
try:
    with open('/tmp/mar_allergies_raw.json') as f:
        allergies_data = json.load(f)
    allergies = allergies_data.get('results', [])
except:
    allergies = []

# Load orders
try:
    with open('/tmp/mar_orders_raw.json') as f:
        orders_data = json.load(f)
    all_orders = orders_data.get('results', [])
except:
    all_orders = []

# Load observations
try:
    with open('/tmp/mar_obs_raw.json') as f:
        obs_data = json.load(f)
    all_obs = obs_data.get('results', [])
except:
    all_obs = []

# Load MySQL order status
try:
    order_status_text = open('/tmp/mar_order_status_raw.txt').read().strip()
    order_status_lines = [l for l in order_status_text.split('\n') if l.strip()]
except:
    order_status_lines = []

current_allergy_count = len(allergies)
current_order_count = len(all_orders)
new_allergies = current_allergy_count - baseline_allergies

# Check for Penicillin in allergy list
penicillin_allergy_found = False
allergy_details = []
for allergy in allergies:
    allergen = allergy.get('allergen', {}) or {}
    coded = allergen.get('codedAllergen', {}) or {}
    non_coded = allergen.get('nonCodedAllergen', '') or ''
    allergen_name = (coded.get('display', '') or coded.get('name', '') or non_coded or '').lower()

    reactions = allergy.get('reactions', []) or []
    reaction_names = [r.get('reaction', {}).get('display', '') for r in reactions]
    severity = (allergy.get('severity', {}) or {}).get('display', '')

    allergy_details.append({
        'allergen': allergen_name,
        'severity': severity,
        'reactions': reaction_names
    })

    if 'penicillin' in allergen_name or 'pen v' in allergen_name or 'pen-v' in allergen_name:
        penicillin_allergy_found = True

# Check Penicillin V order status (voided or discontinued)
penicillin_order_voided = False
penicillin_order_discontinued = False
new_antibiotic_orders = []

# Drugs that are safe alternatives (non-penicillin antibiotics)
safe_antibiotics = [
    'azithromycin', 'erythromycin', 'doxycycline', 'cotrimoxazole', 'trimethoprim',
    'ciprofloxacin', 'levofloxacin', 'clindamycin', 'chloramphenicol', 'metronidazole',
    'tetracycline', 'clarithromycin', 'roxithromycin', 'sulfamethoxazole'
]
# Cross-reactive (NOT acceptable)
cross_reactive = ['amoxicillin', 'ampicillin', 'cephalexin', 'ceftriaxone', 'cefazolin',
                  'cephalosporin', 'cefuroxime', 'cefixime', 'cefadroxil', 'cefalexin']

has_safe_alternative = False

for order in all_orders:
    drug = order.get('drug', {}) or {}
    drug_name = (drug.get('name', '') or drug.get('display', '') or '').lower()
    concept = order.get('concept', {}) or {}
    concept_name = (concept.get('display', '') or '').lower()
    combined_name = drug_name + ' ' + concept_name

    voided = order.get('voided', False)
    date_stopped = order.get('dateStopped')
    order_action = order.get('orderAction', '')

    if 'penicillin' in combined_name:
        if voided or date_stopped or order_action == 'DISCONTINUE':
            penicillin_order_voided = True
            penicillin_order_discontinued = True

    # Check for safe alternative antibiotic (new order)
    if any(ab in combined_name for ab in safe_antibiotics):
        if not any(cr in combined_name for cr in cross_reactive):
            has_safe_alternative = True
            new_antibiotic_orders.append(combined_name.strip())

# Also check MySQL order status text for voided/discontinued Penicillin
order_status_lower = ' '.join(order_status_lines).lower()
if 'penicillin' in order_status_lower:
    lines_with_pen = [l for l in order_status_lines if 'penicillin' in l.lower()]
    for line in lines_with_pen:
        parts = line.split('\t')
        if len(parts) >= 5:
            voided_flag = parts[2].strip()
            date_stopped_val = parts[3].strip()
            order_action_val = parts[4].strip()
            if voided_flag == '1' or date_stopped_val not in ('NULL', '', 'None') or 'DISCONTINUE' in order_action_val:
                penicillin_order_voided = True
                penicillin_order_discontinued = True

# Check clinical note
has_clinical_note = False
note_length = 0
for obs in all_obs:
    value = obs.get('value', '')
    if isinstance(value, str) and len(value) >= 100:
        has_clinical_note = True
        note_length = max(note_length, len(value))

result = {
    "patient_identifier": patient_identifier,
    "patient_uuid": open('/tmp/mar_patient_uuid').read().strip(),
    "baseline_allergy_count": baseline_allergies,
    "current_allergy_count": current_allergy_count,
    "new_allergies": new_allergies,
    "penicillin_allergy_documented": penicillin_allergy_found,
    "allergy_details": allergy_details,
    "baseline_order_count": baseline_orders,
    "current_order_count": current_order_count,
    "penicillin_order_discontinued": penicillin_order_discontinued,
    "has_safe_alternative_antibiotic": has_safe_alternative,
    "new_antibiotic_orders": new_antibiotic_orders[:5],
    "clinical_note": {
        "has_clinical_note": has_clinical_note,
        "note_length": note_length
    }
}

with open('/tmp/medication_allergy_reconciliation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"[EXPORT] Penicillin allergy documented: {penicillin_allergy_found}")
print(f"[EXPORT] Penicillin order discontinued: {penicillin_order_discontinued}")
print(f"[EXPORT] Safe alternative prescribed: {has_safe_alternative}")
print(f"[EXPORT] Clinical note: {has_clinical_note}")
PYEOF

echo "[EXPORT] Result saved to /tmp/medication_allergy_reconciliation_result.json"
cat /tmp/medication_allergy_reconciliation_result.json | python3 -m json.tool > /dev/null 2>&1 && echo "[EXPORT] JSON valid"

echo "=== Export Complete ==="
