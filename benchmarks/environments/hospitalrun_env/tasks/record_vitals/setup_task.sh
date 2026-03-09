#!/bin/bash
echo "=== Setting up record_vitals task ==="

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

# Verify patient Harold Whitmore exists (seeded as patient_p1_000004)
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000004" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('firstName', ''))
" 2>/dev/null || echo "")

if [ -z "$PATIENT_CHECK" ]; then
    echo "Re-seeding patient Harold Whitmore..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000004" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00004",
            "displayName": "Whitmore, Harold",
            "firstName": "Harold",
            "lastName": "Whitmore",
            "sex": "Male",
            "dateOfBirth": "01/30/1953",
            "bloodType": "AB-",
            "status": "Active",
            "address": "56 Pine Circle, Peoria, IL 61602",
            "phone": "217-555-0467",
            "email": "harold.whitmore@example.com",
            "patientType": "Inpatient"
          }
        }' > /dev/null || true
fi

# Verify/re-seed inpatient visit for Harold Whitmore (seeded as visit_p1_000004)
VISIT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000004" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('patient', ''))
" 2>/dev/null || echo "")

if [ -z "$VISIT_CHECK" ]; then
    echo "Re-seeding visit for Harold Whitmore..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000004" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "patient": "patient_p1_000004",
            "visitType": "Inpatient",
            "startDate": "01/08/2025",
            "endDate": "01/11/2025",
            "examiner": "Dr. David Park",
            "location": "Ward 3",
            "reasonForVisit": "CHF exacerbation",
            "status": "admitted"
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
take_screenshot /tmp/record_vitals_initial.png
echo "Task start state screenshot saved to /tmp/record_vitals_initial.png"

echo "=== record_vitals task setup complete ==="
echo "Agent should see: HospitalRun patients list"
echo "Task: Find Harold Whitmore, open visit, record vitals (weight, height, BP, HR, etc.)"
