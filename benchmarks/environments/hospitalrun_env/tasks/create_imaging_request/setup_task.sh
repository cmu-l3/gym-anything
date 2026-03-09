#!/bin/bash
echo "=== Setting up create_imaging_request task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (file creation timestamps)
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available."
        break
    fi
    sleep 2
done

# 2. Verify patient Maria Santos exists (p1_0001)
# If not, seed her data.
echo "Verifying patient Maria Santos..."
PATIENT_DOC=$(hr_couch_get "patient_p1_0001")
if echo "$PATIENT_DOC" | grep -q "error"; then
    echo "Seeding patient Maria Santos..."
    # Create patient doc
    DATA='{
        "data": {
            "friendlyId": "P0001",
            "firstName": "Maria",
            "lastName": "Santos",
            "sex": "Female",
            "dateOfBirth": "1985-03-15",
            "address": "Rua Augusta, São Paulo",
            "phone": "555-0199",
            "patientType": "Outpatient",
            "status": "Active"
        }
    }'
    hr_couch_put "patient_p1_0001" "$DATA"
else
    echo "Patient Maria Santos exists."
fi

# 3. Record initial state of imaging documents
# We will count existing imaging requests to ensure a NEW one is created
echo "Recording initial imaging documents..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
imaging_docs = [
    row['doc'] for row in data.get('rows', []) 
    if row.get('doc', {}).get('type') == 'imaging' 
    or row.get('doc', {}).get('data', {}).get('type') == 'imaging'
]
print(len(imaging_docs))
with open('/tmp/initial_imaging_ids.json', 'w') as f:
    json.dump([d.get('_id') for d in imaging_docs], f)
" > /tmp/initial_imaging_count.txt

echo "Initial imaging count: $(cat /tmp/initial_imaging_count.txt)"

# 4. Ensure Firefox is open and logged in
ensure_hospitalrun_logged_in

# 5. Navigate to Dashboard to start
navigate_firefox_to "http://localhost:3000"

# 6. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="