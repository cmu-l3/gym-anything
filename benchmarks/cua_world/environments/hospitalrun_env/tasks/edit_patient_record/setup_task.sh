#!/bin/bash
set -e
echo "=== Setting up edit_patient_record task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── Ensure Patient James Chen exists with INITIAL values ───────────────────
# We must reset the patient to the starting state to ensure the task is performable
# and reproducible, regardless of previous runs.

echo "Resetting patient James Chen to initial state..."

# Data structure matching HospitalRun's CouchDB schema
# Note: HospitalRun usually wraps data in a 'data' property
INIT_DOC='{
  "data": {
    "firstName": "James",
    "lastName": "Chen",
    "middleName": "Wei",
    "sex": "Male",
    "dateOfBirth": "1978-11-22T00:00:00.000Z",
    "address": "456 Maple Ave",
    "address2": "",
    "city": "Seattle",
    "state": "WA",
    "zipCode": "98101",
    "bloodType": "A+",
    "email": "james.chen@email.com",
    "phone": "555-0102",
    "friendlyId": "P00002",
    "patientId": "P00002",
    "status": "Active",
    "patientType": "Charity",
    "admitted": false
  },
  "type": "patient"
}'

# Check if document exists to get revision for update/delete
DOC_URL="${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000002"
CURRENT_REV=$(curl -s "$DOC_URL" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))" 2>/dev/null || echo "")

if [ -n "$CURRENT_REV" ]; then
    # Update existing doc (PUT with _rev is cleaner than DELETE+PUT which leaves tombstones)
    # We construct the full JSON with _id and _rev
    FULL_DOC=$(echo "$INIT_DOC" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
doc['_id'] = 'patient_p1_000002'
doc['_rev'] = '$CURRENT_REV'
print(json.dumps(doc))
")
    curl -s -X PUT "$DOC_URL" -H "Content-Type: application/json" -d "$FULL_DOC" > /dev/null
    echo "Reset existing record for James Chen."
else
    # Create new doc
    FULL_DOC=$(echo "$INIT_DOC" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
doc['_id'] = 'patient_p1_000002'
print(json.dumps(doc))
")
    curl -s -X PUT "$DOC_URL" -H "Content-Type: application/json" -d "$FULL_DOC" > /dev/null
    echo "Created new record for James Chen."
fi

# Verify the reset worked
CHECK_ADDR=$(curl -s "$DOC_URL" | python3 -c "import sys, json; doc=json.load(sys.stdin); print(doc.get('data', doc).get('address', ''))")
if [ "$CHECK_ADDR" != "456 Maple Ave" ]; then
    echo "ERROR: Failed to reset patient data. Address is: $CHECK_ADDR"
    exit 1
fi

# ─── Standard Environment Setup ─────────────────────────────────────────────

# Fix offline sync loop (common issue in this env)
fix_offline_sync

# Ensure Firefox is fresh and logged in
echo "Launching Firefox..."
ensure_hospitalrun_logged_in

# Navigate to main page
navigate_firefox_to "http://localhost:3000/"

# Wait for DB sync to likely finish
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="