#!/bin/bash
set -e
echo "=== Setting up create_outpatient_visit task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure HospitalRun is accessible
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 3. Apply offline sync fix (standard for this env) to ensure DB writes work
fix_offline_sync

# 4. Seed Patient Elena Martinez (P00201)
echo "Seeding patient Elena Martinez..."
# Check if exists first
PATIENT_ID="patient_p1_00201"
EXISTING_PATIENT=$(hr_couch_get "$PATIENT_ID")
if echo "$EXISTING_PATIENT" | grep -q "\"error\":\"not_found\""; then
    # Create patient doc
    # Structure: root keys + data object (HospitalRun quirk)
    PATIENT_JSON='{
      "data": {
        "friendlyId": "P00201",
        "firstName": "Elena",
        "lastName": "Martinez",
        "dateOfBirth": "1987-04-22",
        "sex": "Female",
        "address": "4521 Cedar Lane, Austin, TX 78701",
        "phone": "512-555-0173",
        "email": "elena.m@example.com",
        "patientType": "Patient",
        "status": "Active"
      },
      "type": "patient"
    }'
    hr_couch_put "$PATIENT_ID" "$PATIENT_JSON"
    echo "Patient seeded."
else
    echo "Patient already exists."
fi

# 5. Clean up any existing visits for this patient to ensure clean verification state
# We search for visits linked to this patient ID
echo "Cleaning up previous visits for P00201..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc) # Handle nested data
    if doc.get('type') == 'visit' or d.get('type') == 'visit':
        if d.get('patient') == '$PATIENT_ID' or d.get('patient') == 'P00201':
            print(doc['_id'] + ' ' + doc['_rev'])
" | while read -r id rev; do
    echo "Deleting old visit $id"
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${id}?rev=${rev}" > /dev/null
done

# 6. Record initial visit count (should be 0 now, but good practice)
INITIAL_COUNT=$(hr_count_docs "visit")
echo "$INITIAL_COUNT" > /tmp/initial_visit_count.txt

# 7. Launch Firefox and login
echo "Launching Firefox..."
# Kill existing firefox to ensure fresh start
pkill -f firefox || true
sleep 1

# Start Firefox pointing to Patients list
su - ga -c "DISPLAY=:1 firefox 'http://localhost:3000/#/patients' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "HospitalRun"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "HospitalRun" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Ensure logged in (handled by task_utils or manual check if needed, 
# but env setup usually handles auth persistence via seeded user db)

# 8. Capture initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="