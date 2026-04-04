#!/bin/bash
echo "=== Setting up add_diagnosis task ==="

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

# Verify patient James Okafor exists (seeded as patient_p1_000002)
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000002" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('firstName', ''))
" 2>/dev/null || echo "")

if [ -z "$PATIENT_CHECK" ]; then
    echo "Re-seeding patient James Okafor..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000002" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00002",
            "displayName": "Okafor, James",
            "firstName": "James",
            "lastName": "Okafor",
            "sex": "Male",
            "dateOfBirth": "07/22/1979",
            "bloodType": "O+",
            "status": "Active",
            "address": "89 Maple Ave, Decatur, IL 62521",
            "phone": "217-555-0278",
            "email": "james.okafor@example.com",
            "patientType": "Outpatient"
          }
        }' > /dev/null || true
fi

# Verify/re-seed visit for James Okafor (seeded as visit_p1_000002)
VISIT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000002" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('patient', ''))
" 2>/dev/null || echo "")

if [ -z "$VISIT_CHECK" ]; then
    echo "Re-seeding visit for James Okafor..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000002" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "patient": "patient_p1_000002",
            "visitType": "Outpatient",
            "startDate": "01/12/2025",
            "endDate": "01/12/2025",
            "examiner": "Dr. James Okonkwo",
            "location": "Clinic B",
            "reasonForVisit": "Diabetes management review",
            "status": "completed"
          }
        }' > /dev/null || true
fi

# Ensure Firefox is open
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for PouchDB to fully connect and patient list to load
echo "Navigating to patient James Okafor..."
wait_for_db_ready

# Take initial screenshot
take_screenshot /tmp/add_diagnosis_initial.png
echo "Task start state screenshot saved to /tmp/add_diagnosis_initial.png"

echo "=== add_diagnosis task setup complete ==="
echo "Agent should see: HospitalRun patients list"
echo "Task: Find James Okafor, open visit, add Type 2 Diabetes Mellitus diagnosis"
