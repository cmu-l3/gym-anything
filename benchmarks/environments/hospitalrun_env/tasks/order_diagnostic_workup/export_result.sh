#!/bin/bash
# Export script for order_diagnostic_workup
# Captures final state of Elena Petrov's diagnostic orders for evidence / debugging.

echo "=== Exporting order_diagnostic_workup result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/order_diagnostic_workup_end.png
echo "Final screenshot saved."

HR_URL="http://couchadmin:test@localhost:5984"
DB="main"

SUMMARY=$(curl -s "${HR_URL}/${DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
EXCLUDE_IDS = {'patient_p1_000011', 'visit_p1_000011'}
LAB_KW = ['lab', 'tsh', 't4', 't3', 'thyroid', 'metabolic', 'cbc', 'panel',
          'blood', 'chemistry', 'hemoglobin', 'glucose', 'creatinine', 'lipid',
          'hematology', 'biochemistry', 'urine', 'culture', 'complete blood',
          'antibod', 'serum']
IMG_KW = ['ultrasound', 'sonogram', 'scan', 'mri', 'ct', 'x-ray', 'xray',
          'imaging', 'iodine', 'scintigraphy', 'echo', 'radiograph', 'nuclear']
result = {'patient_id': 'patient_p1_000011', 'lab_orders': [], 'imaging_orders': []}
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design') or doc_id in EXCLUDE_IDS:
        continue
    d = doc.get('data', doc)
    patient_ref = d.get('patient', doc.get('patient', ''))
    if 'patient_p1_000011' not in patient_ref:
        continue
    doc_str = json.dumps(doc).lower()
    doc_type = (d.get('type') or doc.get('type') or '').lower()
    is_lab = any(kw in doc_str for kw in LAB_KW)
    is_img = any(kw in doc_str for kw in IMG_KW)
    if doc_type in ['lab', 'lab-request', 'labrequest']:
        result['lab_orders'].append(doc_id)
    elif doc_type in ['imaging', 'imaging-request', 'imagingrequest']:
        result['imaging_orders'].append(doc_id)
    elif is_img and not is_lab:
        result['imaging_orders'].append(doc_id)
    elif is_lab:
        result['lab_orders'].append(doc_id)
result['lab_count'] = len(result['lab_orders'])
result['imaging_count'] = len(result['imaging_orders'])
print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{}')

echo "$SUMMARY" > /tmp/order_diagnostic_workup_result.json
echo "CouchDB summary:"
echo "$SUMMARY"

echo "=== Export Complete ==="
