#!/bin/bash
# Export script for complete_outpatient_encounter
# Captures final state of Grace Kim's encounter for evidence / debugging.
# The verifier queries CouchDB live via exec_capture; this script captures
# a final screenshot and a CouchDB summary for audit purposes.

echo "=== Exporting complete_outpatient_encounter result ==="

source /workspace/scripts/task_utils.sh

# Final screenshot
take_screenshot /tmp/complete_outpatient_encounter_end.png
echo "Final screenshot saved."

HR_URL="http://couchadmin:test@localhost:5984"
DB="main"
PATIENT_ID="patient_p1_000013"
VISIT_ID="visit_p1_000013"

# Summarize what was found for Grace Kim
SUMMARY=$(curl -s "${HR_URL}/${DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
result = {'patient_id': 'patient_p1_000013', 'visit_id': 'visit_p1_000013',
          'vitals_found': False, 'diagnosis_found': False, 'medication_found': False,
          'docs_linked': []}
DIAG_KW = ['migraine', 'headache', 'cephalgia', 'cephalea']
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design'):
        continue
    d = doc.get('data', doc)
    patient_ref = d.get('patient', doc.get('patient', ''))
    if 'patient_p1_000013' not in patient_ref:
        continue
    doc_str = json.dumps(doc).lower()
    doc_type = (d.get('type') or doc.get('type') or '').lower()
    if doc_type == 'vitals' or any(f in doc_str for f in ['systolic','heartrate','heart_rate','temperature']):
        result['vitals_found'] = True
    if any(kw in doc_str for kw in DIAG_KW):
        result['diagnosis_found'] = True
    if doc_type == 'medication' or 'medication' in doc_str:
        result['medication_found'] = True
    result['docs_linked'].append(doc_id)
print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{}')

# Save summary JSON
echo "$SUMMARY" > /tmp/complete_outpatient_encounter_result.json

echo "CouchDB summary:"
echo "$SUMMARY"

echo "=== Export Complete ==="
