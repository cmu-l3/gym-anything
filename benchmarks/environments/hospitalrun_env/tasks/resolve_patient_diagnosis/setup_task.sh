#!/bin/bash
set -e
echo "=== Setting up resolve_patient_diagnosis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is ready
# (Helpers in task_utils.sh handle standard checks)
if ! curl -s "http://localhost:3000" > /dev/null; then
    echo "Waiting for HospitalRun..."
    sleep 5
fi

# 2. Seed Patient "Oliver Sacks"
# We use a fixed ID to make tracking easier
PATIENT_ID="patient_oliver_sacks"
# Delete if exists to ensure clean state
hr_couch_delete "$PATIENT_ID" 2>/dev/null || true

PATIENT_DOC=$(cat <<EOF
{
  "type": "patient",
  "data": {
    "firstName": "Oliver",
    "lastName": "Sacks",
    "dateOfBirth": "1960-07-09",
    "sex": "Male",
    "address": "12 Bronx Way",
    "city": "New York",
    "state": "NY",
    "phone": "555-0199",
    "email": "oliver.sacks@example.com",
    "patientType": "Outpatient"
  }
}
EOF
)

echo "Seeding patient Oliver Sacks..."
hr_couch_put "$PATIENT_ID" "$PATIENT_DOC"

# 3. Seed Active Diagnosis "Acute Bronchitis"
# Date: 14 days ago
START_DATE=$(date -d "14 days ago" +%Y-%m-%d)
DIAGNOSIS_ID="diagnosis_oliver_bronchitis"
# Delete if exists
hr_couch_delete "$DIAGNOSIS_ID" 2>/dev/null || true

# Note: HospitalRun diagnosis structure
DIAGNOSIS_DOC=$(cat <<EOF
{
  "type": "diagnosis",
  "data": {
    "patient": "${PATIENT_ID}",
    "diagnosis": "Acute Bronchitis",
    "description": "Productive cough, low grade fever",
    "date": "${START_DATE}",
    "status": "Active",
    "visit": ""
  }
}
EOF
)

echo "Seeding active diagnosis..."
hr_couch_put "$DIAGNOSIS_ID" "$DIAGNOSIS_DOC"

# 4. Record initial count of diagnoses for this patient
# We expect exactly 1 right now.
INITIAL_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" \
    2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    # Check if linked to Oliver Sacks
    patient_ref = d.get('patient', '')
    if patient_ref == '${PATIENT_ID}' or ('Oliver' in str(d) and 'Sacks' in str(d)):
        # Check if it is a diagnosis
        if doc.get('type') == 'diagnosis' or d.get('type') == 'diagnosis' or 'diagnosis' in row['id']:
             count += 1
print(count)
")

echo "$INITIAL_COUNT" > /tmp/initial_diagnosis_count.txt
echo "Initial diagnosis count for patient: $INITIAL_COUNT"

# 5. Ensure Firefox is open and logged in
ensure_hospitalrun_logged_in

# 6. Wait for DB sync
wait_for_db_ready

# 7. Navigate to patient list to start
navigate_firefox_to "http://localhost:3000/#/patients"

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="