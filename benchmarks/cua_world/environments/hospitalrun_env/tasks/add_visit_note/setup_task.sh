#!/bin/bash
set -e
echo "=== Setting up add_visit_note task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Verify HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Seed Patient Elena Vasquez (if not exists)
PATIENT_ID="patient_p1_ev001"
echo "Checking/Seeding patient $PATIENT_ID..."

# Check if patient exists
PATIENT_CHECK=$(hr_couch_get "$PATIENT_ID" | grep -o "Elena" || echo "")

if [ -z "$PATIENT_CHECK" ]; then
    echo "Creating patient Elena Vasquez..."
    hr_couch_put "$PATIENT_ID" '{
      "data": {
        "friendlyId": "P_EV001",
        "firstName": "Elena",
        "lastName": "Vasquez",
        "sex": "Female",
        "dateOfBirth": "1958-07-22",
        "address": "452 Highland Ave, Seattle, WA 98109",
        "phone": "206-555-0199",
        "email": "elena.v@example.com",
        "status": "Active",
        "patientType": "Inpatient",
        "bloodType": "A+"
      }
    }'
else
    echo "Patient Elena Vasquez already exists."
fi

# 3. Seed Active Visit for Elena Vasquez
VISIT_ID="visit_p1_ev001"
echo "Checking/Seeding visit $VISIT_ID..."

VISIT_CHECK=$(hr_couch_get "$VISIT_ID" | grep -o "Community-acquired pneumonia" || echo "")

if [ -z "$VISIT_CHECK" ]; then
    echo "Creating active visit..."
    # Date 3 days ago
    START_DATE=$(date -d "3 days ago" +%m/%d/%Y)
    
    hr_couch_put "$VISIT_ID" "{
      \"data\": {
        \"patient\": \"$PATIENT_ID\",
        \"visitType\": \"Admission\",
        \"startDate\": \"$START_DATE\",
        \"examiner\": \"Dr. Sarah Chen\",
        \"location\": \"Medical Ward 3B\",
        \"reasonForVisit\": \"Community-acquired pneumonia\",
        \"diagnosis\": \"Community-acquired pneumonia\",
        \"status\": \"Admitted\"
      }
    }"
else
    echo "Visit already exists."
fi

# 4. Record initial count of notes containing key phrases (to detect diff)
# We search for "Day 3 progress note" specifically
INITIAL_NOTE_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
    grep -c "Day 3 progress note" || echo "0")
echo "$INITIAL_NOTE_COUNT" > /tmp/initial_note_count.txt

# 5. Launch Firefox and Login
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 6. Navigate to Patients list to start the workflow
echo "Navigating to Patients list..."
wait_for_db_ready
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state setup complete."