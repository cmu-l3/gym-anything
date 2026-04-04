#!/bin/bash
echo "=== Exporting document_past_surgical_history results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_ID=$(cat /tmp/target_patient_id.txt 2>/dev/null || echo "")

# 3. Query CouchDB for procedures
# We are looking for NEW procedures linked to the patient
echo "Querying CouchDB for procedures..."

curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/all_docs.json

# Parse with Python to find the relevant document
# We extract ALL procedures for the patient to analyze in verifier.py
# This allows the verifier to check date/content logic robustly
python3 -c "
import sys, json, re

try:
    with open('/tmp/all_docs.json', 'r') as f:
        data = json.load(f)
except:
    print('[]')
    sys.exit(0)

target_patient = '$PATIENT_ID'
task_start = int('$TASK_START')
results = []

for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    
    # Check if it's a procedure
    doc_type = d.get('type') or d.get('docType') or ''
    # Procedure docs usually have 'procedure' type, but let's be flexible
    is_procedure = (doc_type == 'procedure' or 'procedure' in json.dumps(d).lower())
    
    if not is_procedure:
        continue
        
    # Check linkage to patient
    pat_ref = d.get('patient') or d.get('patientId') or ''
    pat_id = ''
    if isinstance(pat_ref, dict):
        pat_id = pat_ref.get('id') or pat_ref.get('_id') or ''
    else:
        pat_id = str(pat_ref)
        
    if target_patient in pat_id or pat_id == target_patient:
        # Found a procedure for this patient
        results.append({
            'id': doc.get('_id'),
            'procedure_name': d.get('procedure', '') or d.get('description', ''),
            'date': d.get('procedureDate', '') or d.get('date', ''),
            'notes': d.get('notes', ''),
            'full_doc': d
        })

print(json.dumps(results))
" > /tmp/procedures_found.json

# 4. Check if App is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "patient_id": "$PATIENT_ID",
    "procedures": $(cat /tmp/procedures_found.json),
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="