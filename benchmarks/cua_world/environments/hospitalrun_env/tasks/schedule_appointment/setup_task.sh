#!/bin/bash
echo "=== Setting up schedule_appointment task ==="

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

# Clean up any previously scheduled appointments for this task
# Appointment documents store data in a 'data' wrapper in HospitalRun CouchDB format
echo "Cleaning up any previous task appointments..."
EXISTING=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    reason = d.get('reasonForAppointment', d.get('reason', ''))
    patient = d.get('patient', '')
    if 'Blood pressure follow-up consultation' in reason:
        print(row['id'] + '|' + doc.get('_rev',''))
" 2>/dev/null || echo "")

if [ -n "$EXISTING" ]; then
    echo "$EXISTING" | while IFS='|' read -r doc_id rev; do
        if [ -n "$doc_id" ] && [ -n "$rev" ]; then
            curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null || true
            echo "Deleted previous appointment: $doc_id"
        fi
    done
fi

# Verify patient Margaret Chen exists (seeded as patient_p1_000001)
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000001" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('firstName', ''))
" 2>/dev/null || echo "")

if [ -z "$PATIENT_CHECK" ]; then
    echo "WARNING: Patient Margaret Chen (patient_p1_000001) not found. Re-seeding..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000001" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00001",
            "displayName": "Chen, Margaret",
            "firstName": "Margaret",
            "lastName": "Chen",
            "sex": "Female",
            "dateOfBirth": "03/14/1966",
            "bloodType": "A+",
            "status": "Active",
            "address": "412 Willow St, Springfield, IL 62701",
            "phone": "217-555-0142",
            "email": "margaret.chen@example.com",
            "patientType": "Outpatient"
          }
        }' > /dev/null || true
fi

# Ensure Firefox is open and on HospitalRun
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for PouchDB database to connect and patient list to load
wait_for_db_ready

# Navigate to appointment scheduling page (DB is now ready, form renders immediately)
echo "Navigating to new appointment page..."
navigate_firefox_to "http://localhost:3000/#/appointments/new"
sleep 20  # Wait for Ember.js route to render the new appointment form (mainDB already set)

# Take initial screenshot
take_screenshot /tmp/schedule_appointment_initial.png
echo "Task start state screenshot saved to /tmp/schedule_appointment_initial.png"

echo "=== schedule_appointment task setup complete ==="
echo "Agent should see: HospitalRun new appointment scheduling form"
echo "Task: Schedule appointment for Margaret Chen with provided details"
