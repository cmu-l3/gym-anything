#!/bin/bash
# Export script for complete_ed_admission
# Captures final state of David Nakamura's ED admission for evidence / debugging.

echo "=== Exporting complete_ed_admission result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/complete_ed_admission_end.png
echo "Final screenshot saved."

HR_URL="http://couchadmin:test@localhost:5984"
DB="main"

SUMMARY=$(curl -s "${HR_URL}/${DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)

DIAG_KW  = ['acute coronary', 'coronary syndrome', 'acs', 'chest pain', 'angina',
            'myocardial', 'cardiac', 'ami']
LAB_KW   = ['troponin', 'trop', 'cardiac enzyme', 'cardiac marker', 'tnl', 'tni']
IMG_KW   = ['x-ray', 'xray', 'chest', 'radiograph', 'cxr', 'pa and lateral', 'x ray']
MED_KW   = ['aspirin', 'asa', 'acetylsalicylic', '325']
APPT_KW  = ['cardiology', 'cardiac', 'cardiologist', 'heart', 'risk stratification']
VITALS_F = ['systolic', 'diastolic', 'heartrate', 'heart_rate', 'temperature',
            'o2sat', 'spo2', 'weight', 'height', 'respiratoryrate']

result = {
    'patient_found': False,
    'patient_doc_id': None,
    'visit_found': False,
    'vitals_found': False,
    'diagnosis_found': False,
    'lab_order_found': False,
    'imaging_order_found': False,
    'medication_found': False,
    'appointment_found': False,
    'docs_linked': []
}

# First pass: find the patient doc
patient_doc_id = None
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design'):
        continue
    d = doc.get('data', doc)
    first = d.get('firstName', '').lower()
    last = d.get('lastName', '').lower()
    if first == 'david' and last == 'nakamura':
        result['patient_found'] = True
        result['patient_doc_id'] = doc_id
        patient_doc_id = doc_id
        break

if not patient_doc_id:
    # Broader search
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        doc_id = row.get('id', '')
        if doc_id.startswith('_design'):
            continue
        doc_str = json.dumps(doc).lower()
        if 'nakamura' in doc_str and 'david' in doc_str:
            d = doc.get('data', doc)
            if d.get('firstName', '').lower() or d.get('lastName', '').lower():
                result['patient_found'] = True
                result['patient_doc_id'] = doc_id
                patient_doc_id = doc_id
                break

# Second pass: find linked documents
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design'):
        continue
    if patient_doc_id and doc_id == patient_doc_id:
        continue
    d = doc.get('data', doc)
    doc_str = json.dumps(doc).lower()
    doc_type = (d.get('type') or doc.get('type') or '').lower()

    # Check if linked to Nakamura
    patient_ref = d.get('patient', doc.get('patient', ''))
    linked = False
    if patient_doc_id and patient_doc_id in patient_ref:
        linked = True
    elif 'nakamura' in doc_str:
        linked = True

    if not linked:
        continue

    result['docs_linked'].append(doc_id)

    # Classify
    if doc_type in ['visit'] or 'visittype' in doc_str:
        result['visit_found'] = True
    if any(f in doc_str for f in VITALS_F):
        result['vitals_found'] = True
    if any(kw in doc_str for kw in DIAG_KW) and doc_type not in ['patient', 'visit']:
        result['diagnosis_found'] = True
    if doc_type in ['lab', 'lab-request', 'labrequest'] or (any(kw in doc_str for kw in LAB_KW) and doc_type not in ['patient', 'visit', 'diagnosis']):
        result['lab_order_found'] = True
    if doc_type in ['imaging', 'imaging-request', 'imagingrequest'] or any(kw in doc_str for kw in IMG_KW):
        result['imaging_order_found'] = True
    if doc_type in ['medication', 'medication-request', 'prescription'] or any(kw in doc_str for kw in MED_KW):
        result['medication_found'] = True

# Check appointments (may not be linked by patient doc ID)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design'):
        continue
    d = doc.get('data', doc)
    doc_str = json.dumps(doc).lower()
    if any(kw in doc_str for kw in APPT_KW) and 'nakamura' in doc_str:
        result['appointment_found'] = True
        break
    reason = d.get('reasonForAppointment', d.get('reason', '')).lower()
    if any(kw in reason for kw in APPT_KW):
        result['appointment_found'] = True
        break

print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{}')

echo "$SUMMARY" > /tmp/complete_ed_admission_result.json
echo "CouchDB summary:"
echo "$SUMMARY"

echo "=== Export Complete ==="
