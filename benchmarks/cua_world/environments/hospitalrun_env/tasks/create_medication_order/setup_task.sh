#!/bin/bash
echo "=== Setting up create_medication_order task ==="

source /workspace/scripts/task_utils.sh

# Verify HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# Verify patient Aisha Patel exists (seeded as patient_p1_000005)
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000005" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('firstName', ''))
" 2>/dev/null || echo "")

if [ -z "$PATIENT_CHECK" ]; then
    echo "Re-seeding patient Aisha Patel..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000005" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00005",
            "displayName": "Patel, Aisha",
            "firstName": "Aisha",
            "lastName": "Patel",
            "sex": "Female",
            "dateOfBirth": "08/17/1995",
            "bloodType": "O-",
            "status": "Active",
            "address": "780 Elm St, Bloomington, IL 61701",
            "phone": "217-555-0583",
            "email": "aisha.patel@example.com",
            "patientType": "Outpatient"
          }
        }' > /dev/null || true
fi

# Verify/re-seed emergency visit for Aisha Patel (seeded as visit_p1_000005)
VISIT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000005" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('patient', ''))
" 2>/dev/null || echo "")

if [ -z "$VISIT_CHECK" ]; then
    echo "Re-seeding visit for Aisha Patel..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000005" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "patient": "patient_p1_000005",
            "visitType": "Emergency",
            "startDate": "01/20/2025",
            "endDate": "01/20/2025",
            "examiner": "Dr. Lisa Nguyen",
            "location": "Emergency Department",
            "reasonForVisit": "Acute asthma exacerbation",
            "status": "completed"
          }
        }' > /dev/null || true
fi

# Ensure Firefox is open
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for PouchDB to fully connect and patient list to load
echo "Navigating to patients list..."
wait_for_db_ready

# Take initial screenshot
take_screenshot /tmp/create_medication_order_initial.png
echo "Task start state screenshot saved to /tmp/create_medication_order_initial.png"

echo "=== create_medication_order task setup complete ==="
echo "Agent should see: HospitalRun patients list"
echo "Task: Find Aisha Patel, navigate to medications, add Salbutamol prescription"
