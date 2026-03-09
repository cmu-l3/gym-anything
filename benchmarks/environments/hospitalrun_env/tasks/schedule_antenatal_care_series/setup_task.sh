#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up schedule_antenatal_care_series task ==="

# 1. Fix PouchDB loading issues and ensure clean state
# This function is defined in task_utils.sh and is critical for the app to load
fix_offline_sync

# 2. Seed Patient "Fatima Al-Sayed"
echo "Seeding patient Fatima Al-Sayed..."
PATIENT_ID="P-ANC-001"
# HospitalRun CouchDB ID format: patient_p1_{id}
DOC_ID="patient_p1_${PATIENT_ID}"

# Define patient document
# Note: HospitalRun expects data wrapped in 'data' property for some versions,
# but the beta often puts fields at root mixed with data. We'll use the standard structure.
PATIENT_JSON=$(cat <<EOF
{
  "patientId": "${PATIENT_ID}",
  "firstName": "Fatima",
  "lastName": "Al-Sayed",
  "sex": "Female",
  "dateOfBirth": "1998-05-15T00:00:00.000Z",
  "address": "123 Palm Grove, District 4",
  "phone": "555-0199",
  "type": "patient",
  "audit": {
    "createdBy": "admin",
    "createdDate": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  }
}
EOF
)

# Put patient to DB using helper
# The helper handles the wrap in 'data' if necessary, but here we construct the raw PUT
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${DOC_ID}" \
    -H "Content-Type: application/json" \
    -d "{\"data\": $PATIENT_JSON, \"type\": \"patient\"}" || true

echo "Patient seeded."

# 3. Clean up any existing appointments for this patient (idempotency)
# We want to ensure the agent creates NEW appointments, not verifying old ones.
echo "Cleaning old appointments for this patient..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    # HospitalRun stores appointment data inside 'data' key usually
    d = doc.get('data', doc)
    
    # Check if it's an appointment linked to our patient
    # Patient ref might be the ID string or the doc ID
    patient_ref = d.get('patient', '')
    type_ref = d.get('type', doc.get('type', ''))
    
    if type_ref == 'appointment' and ('${PATIENT_ID}' in patient_ref or 'Fatima' in str(d)):
        print(doc['_id'] + ' ' + doc['_rev'])
" | while read -r doc_id rev; do
    echo "Deleting old appointment: $doc_id"
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}"
done

# 4. Record start time for verification (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox and login
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 6. Navigate to Appointments page to start
echo "Navigating to Appointments..."
navigate_firefox_to "http://localhost:3000/#/appointments"
sleep 5

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="