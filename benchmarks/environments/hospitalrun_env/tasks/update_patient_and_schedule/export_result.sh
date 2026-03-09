#!/bin/bash
# Export script for update_patient_and_schedule
# Captures final state of Robert Kowalski's demographics and follow-up appointment.

echo "=== Exporting update_patient_and_schedule result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/update_patient_and_schedule_end.png
echo "Final screenshot saved."

HR_URL="http://couchadmin:test@localhost:5984"
DB="main"

SUMMARY=$(curl -s "${HR_URL}/${DB}/patient_p1_000006" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
result = {
    'patient_id': 'patient_p1_000006',
    'current_phone': d.get('phone', ''),
    'current_address': d.get('address', ''),
    'phone_updated': '617-555-0284' in str(d.get('phone', '')),
    'address_updated_city': 'boston' in str(d.get('address', '')).lower(),
    'address_updated_street': 'oak' in str(d.get('address', '')).lower()
}
print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{}')

# Also check for new appointment
APPT_SUMMARY=$(curl -s "${HR_URL}/${DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
result = {'appointments_found': [], 'back_pain_appt': False}
BACK_KW = ['back', 'lumbar', 'spine', 'spinal', 'musculoskeletal']
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design'):
        continue
    d = doc.get('data', doc)
    doc_type = (d.get('type') or doc.get('type') or '').lower()
    doc_str = json.dumps(doc).lower()
    patient_ref = d.get('patient', doc.get('patient', ''))
    if 'patient_p1_000006' in patient_ref:
        if doc_type == 'appointment' or 'appointment' in doc_str:
            result['appointments_found'].append(doc_id)
            if any(kw in doc_str for kw in BACK_KW):
                result['back_pain_appt'] = True
print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{}')

# Merge into final result
FINAL=$(python3 -c "
import json, sys
a = json.loads('$SUMMARY'.replace(\"'\", '\"') if '$SUMMARY' else '{}')
b = json.loads('$APPT_SUMMARY'.replace(\"'\", '\"') if '$APPT_SUMMARY' else '{}')
a.update(b)
print(json.dumps(a, indent=2))
" 2>/dev/null || echo "{}")

echo "$FINAL" > /tmp/update_patient_and_schedule_result.json
echo "Patient data:"
echo "$SUMMARY"
echo "Appointment data:"
echo "$APPT_SUMMARY"

echo "=== Export Complete ==="
