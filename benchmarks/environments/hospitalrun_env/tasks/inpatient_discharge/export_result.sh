#!/bin/bash
# Export script for inpatient_discharge
# Captures final state of Arthur Jensen's inpatient stay for evidence / debugging.

echo "=== Exporting inpatient_discharge result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/inpatient_discharge_end.png
echo "Final screenshot saved."

HR_URL="http://couchadmin:test@localhost:5984"
DB="main"

SUMMARY=$(curl -s "${HR_URL}/${DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
result = {'patient_id': 'patient_p1_000014', 'visit_id': 'visit_p1_000014',
          'vitals_found': False, 'diagnosis_found': False, 'medication_found': False,
          'visit_discharged': False, 'visit_status': None, 'docs_linked': []}
COPD_KW = ['copd', 'chronic obstructive', 'emphysema', 'bronchitis']
RESP_KW = ['bronchodilator', 'albuterol', 'salbutamol', 'ipratropium', 'tiotropium',
           'salmeterol', 'formoterol', 'fluticasone', 'budesonide', 'respiratory',
           'inhaler', 'nebulizer', 'oxygen', 'prednisone', 'methylprednisolone']
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design'):
        continue
    d = doc.get('data', doc)
    patient_ref = d.get('patient', doc.get('patient', ''))
    doc_str = json.dumps(doc).lower()
    doc_type = (d.get('type') or doc.get('type') or '').lower()
    if doc_id == 'visit_p1_000014':
        result['visit_status'] = d.get('status', None)
        if d.get('status', '').lower() in ['discharged', 'completed', 'closed']:
            result['visit_discharged'] = True
        if d.get('checkoutDate') or d.get('checkout_date') or d.get('dischargeDate'):
            result['visit_discharged'] = True
        continue
    if 'patient_p1_000014' not in patient_ref:
        continue
    if doc_type == 'vitals' or any(f in doc_str for f in ['systolic','heartrate','heart_rate','temperature']):
        result['vitals_found'] = True
    if any(kw in doc_str for kw in COPD_KW):
        result['diagnosis_found'] = True
    if doc_type == 'medication' or any(kw in doc_str for kw in RESP_KW):
        result['medication_found'] = True
    result['docs_linked'].append(doc_id)
print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{}')

echo "$SUMMARY" > /tmp/inpatient_discharge_result.json
echo "CouchDB summary:"
echo "$SUMMARY"

echo "=== Export Complete ==="
