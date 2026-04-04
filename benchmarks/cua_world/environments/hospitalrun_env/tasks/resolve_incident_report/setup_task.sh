#!/bin/bash
echo "=== Setting up resolve_incident_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Start HospitalRun and wait for readiness
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Seed Incident Data directly into CouchDB
echo "Seeding incident reports..."

# Define timestamp for consistency
NOW=$(date +%s%3N)

# Target Incident: Broken Wheelchair (Status: Reported)
# ID: incident_p1_000001
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/incident_p1_000001" \
    -H "Content-Type: application/json" \
    -d '{
    "type": "incident",
    "userPrefix": "p1",
    "data": {
        "date": "'$NOW'",
        "department": "Ward 3",
        "description": "Broken Wheelchair in Ward 3. Front left wheel is wobbly.",
        "status": "Reported",
        "reportedBy": "Nurse Joy"
    }
}' > /dev/null

# Distractor 1: Medication Spill (Status: Reported)
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/incident_p1_000002" \
    -H "Content-Type: application/json" \
    -d '{
    "type": "incident",
    "userPrefix": "p1",
    "data": {
        "date": "'$NOW'",
        "department": "Pharmacy",
        "description": "Medication Spill in Pharmacy. 500ml of saline.",
        "status": "Reported",
        "reportedBy": "Pharmacist Bob"
    }
}' > /dev/null

# Distractor 2: Patient Fall (Status: Reported)
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/incident_p1_000003" \
    -H "Content-Type: application/json" \
    -d '{
    "type": "incident",
    "userPrefix": "p1",
    "data": {
        "date": "'$NOW'",
        "department": "Room 102",
        "description": "Patient Fall in Room 102. No injury observed.",
        "status": "Reported",
        "reportedBy": "Dr. Smith"
    }
}' > /dev/null

echo "Incidents seeded."

# 3. Prepare Environment (Browser, Login)
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 4. Navigate to Incidents list (to ensure data loads)
wait_for_db_ready
navigate_firefox_to "http://localhost:3000/#/incidents"
sleep 5

# 5. Record Initial State
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/resolve_incident_initial.png

echo "=== Setup complete ==="