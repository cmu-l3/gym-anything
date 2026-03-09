#!/bin/bash
echo "=== Setting up launch_telehealth_service task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ >/dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 2. Reset 'Visit Type' lookup list (Ensure 'Telehealth' is NOT present)
echo "Resetting Visit Type configuration..."
# Get current doc
VISIT_TYPE_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_type")

# Check if document exists
if echo "$VISIT_TYPE_DOC" | grep -q "error"; then
    # Create default if missing
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_type" \
        -H "Content-Type: application/json" \
        -d '{
            "type": "lookup",
            "name": "Visit Type",
            "values": ["Admission", "Check In", "Clinic", "Consultation", "Follow Up"]
        }'
else
    # Remove "Telehealth" if it exists
    CLEAN_DOC=$(echo "$VISIT_TYPE_DOC" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
if 'Telehealth' in doc.get('values', []):
    doc['values'] = [v for v in doc['values'] if v != 'Telehealth']
    print(json.dumps(doc))
else:
    print('')
")
    if [ -n "$CLEAN_DOC" ]; then
        curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_type" \
            -H "Content-Type: application/json" \
            -d "$CLEAN_DOC"
        echo "Removed existing Telehealth entry from configuration."
    fi
fi

# 3. Seed Patient 'Lars Jensen'
echo "Seeding patient Lars Jensen..."
PATIENT_ID="patient_p1_larsjensen"
PATIENT_CHECK=$(hr_couch_get "$PATIENT_ID")

if echo "$PATIENT_CHECK" | grep -q "error"; then
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P-LARS",
            "displayName": "Jensen, Lars",
            "firstName": "Lars",
            "lastName": "Jensen",
            "sex": "Male",
            "dateOfBirth": "1980-05-15",
            "bloodType": "A+",
            "address": "456 Fjord Ave, Minneapolis, MN",
            "phone": "612-555-0100",
            "email": "lars.jensen@example.com",
            "patientType": "Outpatient"
          },
          "type": "patient"
        }'
    echo "Patient Lars Jensen created."
else
    echo "Patient Lars Jensen already exists."
fi

# 4. Clear any existing appointments for Lars Jensen on the target date to prevent confusion
echo "Cleaning up old appointments..."
# Note: Complex query, simpler to just let the agent create a new one.
# We will verify creation time > task start time.

# 5. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in
wait_for_db_ready

# Navigate to home
navigate_firefox_to "http://localhost:3000"

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state recorded."

echo "=== Setup Complete ==="