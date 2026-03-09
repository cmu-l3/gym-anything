#!/bin/bash
# Export script for emergency_triage_workup
# Captures final triage state for Priya Sharma for evidence / debugging.

echo "=== Exporting emergency_triage_workup result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/emergency_triage_workup_end.png
echo "Final screenshot saved."

HR_URL="http://couchadmin:test@localhost:5984"
DB="main"

SUMMARY=$(curl -s "${HR_URL}/${DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
EXCLUDE_IDS = {'patient_p1_000015', 'visit_p1_000015'}
VITALS_F = ['systolic', 'diastolic', 'heartrate', 'heart_rate', 'temperature',
            'o2sat', 'spo2', 'weight', 'height', 'respiratoryrate']
DIAG_KW = ['appendicitis', 'appendix', 'abdom', 'acute', 'peritonitis', 'rlq']
LAB_KW  = ['cbc', 'complete blood', 'differential', 'crp', 'c-reactive', 'white blood',
            'wbc', 'lab', 'blood', 'panel', 'hematology', 'biochemistry', 'chemistry',
            'culture', 'urine', 'serum', 'hemoglobin']
IMG_KW  = ['ct', 'computed tomography', 'ultrasound', 'sonogram', 'abdomen', 'pelvis',
           'imaging', 'scan', 'mri', 'x-ray', 'xray', 'radiograph']
result = {'patient_id': 'patient_p1_000015', 'vitals_found': False,
          'diagnosis_found': False, 'lab_order_found': False,
          'imaging_order_found': False, 'docs_linked': []}
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design') or doc_id in EXCLUDE_IDS:
        continue
    d = doc.get('data', doc)
    patient_ref = d.get('patient', doc.get('patient', ''))
    doc_str = json.dumps(doc).lower()
    if 'patient_p1_000015' not in patient_ref and 'sharma' not in doc_str:
        continue
    doc_type = (d.get('type') or doc.get('type') or '').lower()
    if any(f in doc_str for f in VITALS_F):
        result['vitals_found'] = True
    if any(kw in doc_str for kw in DIAG_KW) and doc_type not in ['patient', 'visit']:
        result['diagnosis_found'] = True
    has_lab = any(kw in doc_str for kw in LAB_KW)
    has_img = any(kw in doc_str for kw in IMG_KW)
    if doc_type in ['lab', 'lab-request', 'labrequest'] or (has_lab and not has_img):
        result['lab_order_found'] = True
    if doc_type in ['imaging', 'imaging-request', 'imagingrequest'] or has_img:
        result['imaging_order_found'] = True
    result['docs_linked'].append(doc_id)
print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{}')

echo "$SUMMARY" > /tmp/emergency_triage_workup_result.json
echo "CouchDB summary:"
echo "$SUMMARY"

echo "=== Export Complete ==="
