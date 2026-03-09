#!/bin/bash
set -e
echo "=== Setting up create_lab_request task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for HospitalRun to be responsive
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    if curl -s http://localhost:3000/ >/dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Ensure Patient P00001 is "Kwame Mensah"
# The default seed might differ, so we force-update or create this specific patient.
echo "Ensuring patient Kwame Mensah (P00001) exists..."

# CouchDB Doc ID for P00001 is usually patient_p1_1 based on the seeding script logic (userPrefix + sequence)
# We will upsert this document to match our task requirements exactly.
PATIENT_DOC_ID="patient_p1_1"

# Check if doc exists to get rev
REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_DOC_ID}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")

PATIENT_JSON='{
  "data": {
    "friendlyId": "P00001",
    "firstName": "Kwame",
    "lastName": "Mensah",
    "sex": "Male",
    "dateOfBirth": "1985-03-15T00:00:00.000Z",
    "phone": "555-0199",
    "address": "123 Accra Road",
    "city": "Kumasi",
    "status": "Active",
    "patientType": "Charity",
    "type": "patient"
  },
  "type": "patient"
}'

if [ -n "$REV" ]; then
    # Update existing
    echo "Updating existing patient P00001..."
    # Inject rev into JSON
    FINAL_JSON=$(echo "$PATIENT_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); d['_rev']='$REV'; print(json.dumps(d))")
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_DOC_ID}" \
        -H "Content-Type: application/json" \
        -d "$FINAL_JSON" > /dev/null
else
    # Create new
    echo "Creating new patient P00001..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_DOC_ID}" \
        -H "Content-Type: application/json" \
        -d "$PATIENT_JSON" > /dev/null
fi

# 3. Record initial count of Lab requests for this patient
# We query by type 'lab' and check the patient field
echo "Recording initial lab request count..."
INITIAL_LABS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc) # Handle nested data wrapper
    # Check if type is lab
    if doc.get('type') == 'lab' or d.get('type') == 'lab':
        # Check if linked to P00001
        p_ref = d.get('patient', '')
        if 'Kwame' in p_ref or 'Mensah' in p_ref or 'P00001' in p_ref or 'patient_p1_1' in p_ref:
            count += 1
print(count)
")
echo "$INITIAL_LABS" > /tmp/initial_lab_count.txt
echo "Initial labs for P00001: $INITIAL_LABS"

# 4. Ensure Firefox is running and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 5. Navigate to Dashboard or Labs to start
navigate_firefox_to "http://localhost:3000/"

# 6. Initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial setup complete."