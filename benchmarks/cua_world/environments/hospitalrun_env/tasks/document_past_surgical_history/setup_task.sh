#!/bin/bash
echo "=== Setting up document_past_surgical_history task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is accessible
echo "Checking HospitalRun availability..."
wait_for_hospitalrun_port 3000

# 2. Ensure Patient "Carlos Gomez" exists
echo "Checking/Creating patient Carlos Gomez..."

# Check if patient exists by name
EXISTING_PATIENT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
found_id = ''
for row in data.get('rows', []):
    doc = row.get('doc', {})
    # Check top level or data wrapper
    d = doc.get('data', doc)
    if d.get('firstName', '').lower() == 'carlos' and d.get('lastName', '').lower() == 'gomez':
        found_id = doc.get('_id')
        break
print(found_id)
" 2>/dev/null || echo "")

if [ -z "$EXISTING_PATIENT" ]; then
    echo "Creating patient Carlos Gomez..."
    # Create patient doc
    PATIENT_ID="patient_p1_$(date +%s)"
    
    # We put data inside 'data' wrapper as HospitalRun often expects
    PATIENT_JSON=$(cat <<EOF
{
  "firstName": "Carlos",
  "lastName": "Gomez",
  "sex": "Male",
  "dateOfBirth": "1980-05-10T00:00:00.000Z",
  "patientType": "Charity",
  "phone": "555-0199",
  "address": "123 Oak St",
  "type": "patient",
  "docType": "patient",
  "data": {
    "firstName": "Carlos",
    "lastName": "Gomez",
    "sex": "Male",
    "dateOfBirth": "1980-05-10T00:00:00.000Z",
    "patientType": "Charity",
    "phone": "555-0199",
    "address": "123 Oak St"
  }
}
EOF
)
    hr_couch_put "$PATIENT_ID" "$PATIENT_JSON"
    EXISTING_PATIENT="$PATIENT_ID"
    sleep 2
else
    echo "Patient Carlos Gomez already exists ($EXISTING_PATIENT)."
fi

# Save patient ID for export script
echo "$EXISTING_PATIENT" > /tmp/target_patient_id.txt

# 3. Clean up any existing procedures for this patient
# We don't want old runs to confuse verification
echo "Cleaning up existing procedures for Carlos Gomez..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
target_pat = '$EXISTING_PATIENT'
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    
    # Check if doc is a procedure/operative plan linked to this patient
    # Type can be 'procedure', 'operativePlan', or just inferred from fields
    doc_type = d.get('type') or d.get('docType') or ''
    
    # Check linkage
    pat_ref = d.get('patient') or d.get('patientId') or ''
    if isinstance(pat_ref, dict):
        pat_ref = pat_ref.get('id') or pat_ref.get('_id') or ''
        
    is_procedure = (doc_type == 'procedure' or 'operative' in doc_type.lower())
    
    if is_procedure and (target_pat in pat_ref or pat_ref == target_pat):
        print(doc.get('_id'))
" | while read -r proc_id; do
    if [ -n "$proc_id" ]; then
        echo "Deleting old procedure: $proc_id"
        hr_couch_delete "$proc_id"
    fi
done

# 4. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in
wait_for_db_ready

# Navigate to Patients list to start
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="