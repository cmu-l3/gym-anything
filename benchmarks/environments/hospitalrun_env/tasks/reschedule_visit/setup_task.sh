#!/bin/bash
echo "=== Setting up reschedule_visit task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Verify HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ >/dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 2. Seed Patient Data (Cameron Howe)
echo "Seeding patient Cameron Howe..."
# ID: patient_p1_cameron
# Note: HospitalRun requires specific field structures. 
# We use 'p1' prefix which matches the userPrefix of hradmin to ensure visibility if strict permissions apply.
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_cameron" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "friendlyId": "P-CAMERON",
        "displayName": "Howe, Cameron",
        "firstName": "Cameron",
        "lastName": "Howe",
        "sex": "Female",
        "dateOfBirth": "1990-05-20",
        "status": "Active",
        "address": "2048 Hardware Lane, Silicon Valley, CA",
        "phone": "555-0199",
        "email": "cameron@mutiny.com",
        "patientType": "Outpatient",
        "type": "patient"
      }
    }' > /dev/null

# 3. Seed Visit Data (Oct 10, 2026)
echo "Seeding appointment for Oct 10, 2026..."
# ID: visit_p1_cameron_v1
# HospitalRun visit document structure
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_cameron_v1" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "patient": "patient_p1_cameron",
        "visitType": "Clinic",
        "startDate": "2026-10-10T10:00:00.000Z",
        "endDate": "2026-10-10T10:30:00.000Z",
        "examiner": "Dr. Bosworth",
        "location": "Main Clinic",
        "reasonForVisit": "General Checkup",
        "status": "scheduled",
        "type": "visit"
      }
    }' > /dev/null

# 4. Record Initial Revision (Anti-gaming)
# We need to know the _rev of the visit doc BEFORE the agent touches it.
# If the agent deletes and creates a new one, the ID might change or creation time will verify it.
# If they edit it, the ID stays same but _rev updates.
VISIT_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_cameron_v1")
INITIAL_REV=$(echo "$VISIT_DOC" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$INITIAL_REV" > /tmp/initial_visit_rev.txt
echo "Initial Visit Rev: $INITIAL_REV"

# 5. Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 6. Wait for PouchDB sync
wait_for_db_ready

# 7. Navigate to Appointments List to start
echo "Navigating to Appointments..."
navigate_firefox_to "http://localhost:3000/#/appointments"
sleep 5

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state captured."

echo "=== Task setup complete ==="