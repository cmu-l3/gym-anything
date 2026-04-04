#!/bin/bash
echo "=== Setting up correct_medication_dosage task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for HospitalRun availability
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Seed Patient: Arthur Dent
# We use a fixed ID for reliability
PATIENT_ID="patient_p1_arthurdent"
echo "Seeding patient Arthur Dent ($PATIENT_ID)..."

# Check if exists, delete if so (clean state)
EXISTING_REV=$(hr_couch_get "$PATIENT_ID" | python3 -c "import sys,json; print(json.load(sys.stdin).get('_rev',''))" 2>/dev/null || echo "")
if [ -n "$EXISTING_REV" ]; then
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}?rev=${EXISTING_REV}" > /dev/null
fi

# Create patient
PATIENT_DOC=$(cat <<EOF
{
  "data": {
    "friendlyId": "P_ARTHUR",
    "firstName": "Arthur",
    "lastName": "Dent",
    "sex": "Male",
    "dateOfBirth": "1980-05-11",
    "address": "155 Country Lane, Cottington",
    "phone": "555-4242",
    "patientType": "Outpatient",
    "status": "Active"
  }
}
EOF
)
hr_couch_put "${PATIENT_ID}" "${PATIENT_DOC}"

# 3. Seed Incorrect Medication Order
# ID needs to be unique and identifiable
MED_ID="medication_${PATIENT_ID}_med_amox_001"
echo "Seeding incorrect medication order ($MED_ID)..."

# Delete if exists
MED_REV=$(hr_couch_get "$MED_ID" | python3 -c "import sys,json; print(json.load(sys.stdin).get('_rev',''))" 2>/dev/null || echo "")
if [ -n "$MED_REV" ]; then
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${MED_ID}?rev=${MED_REV}" > /dev/null
fi

# Create medication with 2000mg error
# HospitalRun medication docs link to patient via 'patient' field
MED_DOC=$(cat <<EOF
{
  "data": {
    "patient": "${PATIENT_ID}",
    "medication": "Amoxicillin",
    "dosage": "2000mg",
    "frequency": "Three times daily",
    "status": "Requested",
    "prescriptionDate": "$(date +%m/%d/%Y)",
    "quantity": "30",
    "refills": "0",
    "prescribedBy": "Dr. Ford Prefect"
  }
}
EOF
)
hr_couch_put "${MED_ID}" "${MED_DOC}"

# 4. Record initial state for verification logic
echo "Initial State: Medication $MED_ID seeded with dosage 2000mg"
echo "$MED_ID" > /tmp/target_med_id.txt

# 5. Browser Setup
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for PouchDB sync
wait_for_db_ready

# Navigate specifically to the patient list to ensure agent sees the patient
navigate_firefox_to "http://localhost:3000/#/patients"

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="