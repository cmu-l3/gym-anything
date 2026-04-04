#!/bin/bash
set -e
echo "=== Setting up dispense_patient_medication task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for HospitalRun to be ready
echo "Checking HospitalRun availability..."
wait_for_db_ready

# 2. Define IDs
PATIENT_SVEN="patient_sven_goran"
PATIENT_JANICE="patient_janice_joplin"
MED_TARGET="medication_target_sven"
MED_CANCELLED="medication_distractor_sven_cancelled"
MED_OTHER="medication_distractor_janice"

# 3. Clean up previous data (Idempotency)
echo "Cleaning up old data..."
hr_couch_delete "$MED_TARGET" || true
hr_couch_delete "$MED_CANCELLED" || true
hr_couch_delete "$MED_OTHER" || true
hr_couch_delete "$PATIENT_SVEN" || true
hr_couch_delete "$PATIENT_JANICE" || true

# 4. Seed Patients
echo "Seeding patients..."

# Sven Goran
hr_couch_put "$PATIENT_SVEN" '{
  "data": {
    "friendlyId": "P-SVEN",
    "firstName": "Sven",
    "lastName": "Goran",
    "sex": "Male",
    "dateOfBirth": "1980-05-20",
    "status": "Active",
    "patientType": "Outpatient"
  }
}'

# Janice Joplin (Distractor)
hr_couch_put "$PATIENT_JANICE" '{
  "data": {
    "friendlyId": "P-JANICE",
    "firstName": "Janice",
    "lastName": "Joplin",
    "sex": "Female",
    "dateOfBirth": "1970-01-19",
    "status": "Active",
    "patientType": "Outpatient"
  }
}'

# 5. Seed Medication Orders
echo "Seeding medication orders..."

# Target: Sven - Ibuprofen (New)
# Note: status "New" is the starting state for a requested med
hr_couch_put "$MED_TARGET" "{
  \"data\": {
    \"patient\": \"$PATIENT_SVEN\",
    \"medication\": \"Ibuprofen 400mg\",
    \"status\": \"New\",
    \"priority\": \"Routine\",
    \"requestedBy\": \"Dr. House\",
    \"requestedDate\": \"$(date +%s)000\",
    \"quantity\": 30,
    \"refills\": 0
  }
}"

# Distractor 1: Sven - Amoxicillin (Cancelled)
hr_couch_put "$MED_CANCELLED" "{
  \"data\": {
    \"patient\": \"$PATIENT_SVEN\",
    \"medication\": \"Amoxicillin 500mg\",
    \"status\": \"Cancelled\",
    \"priority\": \"Urgent\",
    \"requestedBy\": \"Dr. House\",
    \"requestedDate\": \"$(date -d 'yesterday' +%s)000\",
    \"quantity\": 20,
    \"refills\": 0
  }
}"

# Distractor 2: Janice - Ibuprofen (New) - Should NOT be touched
hr_couch_put "$MED_OTHER" "{
  \"data\": {
    \"patient\": \"$PATIENT_JANICE\",
    \"medication\": \"Ibuprofen 400mg\",
    \"status\": \"New\",
    \"priority\": \"Routine\",
    \"requestedBy\": \"Dr. Wilson\",
    \"requestedDate\": \"$(date +%s)000\",
    \"quantity\": 30,
    \"refills\": 2
  }
}"

# 6. Record Start Time and Counts
date +%s > /tmp/task_start_time.txt
# Verify the target exists and has status New
INITIAL_STATUS=$(hr_couch_get "$MED_TARGET" | python3 -c "import sys, json; print(json.load(sys.stdin).get('data', {}).get('status', 'Error'))")
echo "Initial Target Status: $INITIAL_STATUS"
if [ "$INITIAL_STATUS" != "New" ]; then
    echo "ERROR: Failed to seed target medication correctly."
    exit 1
fi

# 7. Setup Browser
echo "Launching browser..."
ensure_hospitalrun_logged_in

# Navigate to Medication section specifically to help agent start close to context
navigate_firefox_to "http://localhost:3000/#/medication"
sleep 5

# 8. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="