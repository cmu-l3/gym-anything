#!/bin/bash
set -e
echo "=== Setting up admit_patient_to_ward task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
wait_for_hospitalrun 30

# 2. Seed Patient Data (Sarah Connor)
# We use a specific ID to ensure we can find her easily later
PATIENT_ID="patient_p1_adt101"
PATIENT_FRIENDLY_ID="P-ADT-101"

echo "Seeding patient Sarah Connor..."
# Check if exists, if not create
PATIENT_CHECK=$(hr_couch_get "$PATIENT_ID" | grep "Sarah") || true

if [ -z "$PATIENT_CHECK" ]; then
    # Create patient doc
    # Note: HospitalRun expects data wrapped in "data" property
    cat <<EOF > /tmp/patient_seed.json
{
  "data": {
    "friendlyId": "$PATIENT_FRIENDLY_ID",
    "firstName": "Sarah",
    "lastName": "Connor",
    "sex": "Female",
    "dateOfBirth": "1984-05-12",
    "phone": "555-0199",
    "address": "123 Cyberdyne Sys, Los Angeles, CA",
    "status": "Active",
    "patientType": "Patient"
  },
  "type": "patient"
}
EOF
    hr_couch_put "$PATIENT_ID" "$(cat /tmp/patient_seed.json)"
    echo "Patient seeded."
else
    echo "Patient already exists."
fi

# 3. Clean up any existing VISITS for this patient to ensure clean state
# We look for visits linked to this patient ID
echo "Cleaning up previous visits..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
python3 -c "
import sys, json
data = json.load(sys.stdin)
target_pat = '$PATIENT_ID'
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    # Check if doc is a visit and linked to our patient
    if (doc.get('type') == 'visit' or d.get('type') == 'visit') and \
       (d.get('patient') == target_pat or d.get('patientId') == target_pat):
        print(f\"{doc['_id']} {doc['_rev']}\")
" | while read -r id rev; do
    echo "Deleting old visit: $id"
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${id}?rev=${rev}"
done

# 4. Prepare Browser
echo "Ensuring Firefox is ready..."
fix_offline_sync  # Fix PouchDB sync issues
ensure_hospitalrun_logged_in

# 5. Navigate to Patient List to start
echo "Navigating to Patients list..."
navigate_firefox_to "${HR_URL}/#/patients"

# 6. Record Start Time and Initial State
date +%s > /tmp/task_start_time.txt

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="