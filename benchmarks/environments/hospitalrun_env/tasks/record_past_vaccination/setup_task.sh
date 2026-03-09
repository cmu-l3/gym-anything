#!/bin/bash
echo "=== Setting up record_past_vaccination task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming (creation timestamp check)
date +%s > /tmp/task_start_time.txt

# 2. Wait for HospitalRun
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 3. Seed Patient "Lucas Silva"
# We'll use a specific ID to make verification reliable
PATIENT_DOC_ID="patient_p1_vacc_001"
FRIENDLY_ID="P_VACC_001"

echo "Seeding patient Lucas Silva..."

# Delete if exists (idempotency)
EXISTING_REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_DOC_ID}" | jq -r ._rev)
if [ "$EXISTING_REV" != "null" ]; then
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_DOC_ID}?rev=${EXISTING_REV}" > /dev/null
fi

# Create Patient
# HospitalRun data structure: Root doc has _id, type, and usually a 'data' property wrapping fields
# but sometimes fields are at root depending on version. HR v1 usually puts them in `data`.
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_DOC_ID}" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "firstName": "Lucas",
        "lastName": "Silva",
        "friendlyId": "'"$FRIENDLY_ID"'",
        "sex": "Male",
        "dateOfBirth": "2019-05-20T00:00:00.000Z",
        "address": "456 Pine St",
        "phone": "555-0199",
        "patientType": "Pediatric",
        "status": "Active"
      },
      "type": "patient"
    }' > /dev/null

echo "Patient seeded."

# 4. Clean up any pre-existing procedures for this patient (to ensure fresh task)
# Scan for procedures linked to this patient ID
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc) # Handle wrapped data
    
    # Check if it's a procedure for our patient
    is_proc = doc.get('type') == 'procedure' or d.get('type') == 'procedure'
    
    # Check linkage (patient field might be the ID string or an object)
    pat_ref = d.get('patient', '')
    is_linked = '$PATIENT_DOC_ID' in str(pat_ref) or '$FRIENDLY_ID' in str(pat_ref)
    
    if is_proc and is_linked:
        print(doc['_id'] + ' ' + doc['_rev'])
" | while read -r id rev; do
    echo "Deleting stale procedure: $id"
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${id}?rev=${rev}" > /dev/null
done

# 5. Prepare Browser
echo "Ensuring Firefox is ready..."
# This helper (from task_utils) handles killing stale firefox, fixing pouchdb, and logging in
ensure_hospitalrun_logged_in

# Navigate to Patients list to start
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="