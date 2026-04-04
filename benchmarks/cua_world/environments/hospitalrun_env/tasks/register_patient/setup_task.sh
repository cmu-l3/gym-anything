#!/bin/bash
echo "=== Setting up register_patient task ==="

source /workspace/scripts/task_utils.sh

# Verify HospitalRun and CouchDB are running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    echo "Waiting for HospitalRun (attempt $i)..."
    sleep 5
done

# Remove any previously registered test patient Samuel Oduya (for idempotency)
echo "Cleaning up any previous test patient data..."
# Search for existing docs with lastName Oduya and delete them
EXISTING=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    # Check both top-level fields and nested 'data' field (HospitalRun wraps in data)
    d = doc.get('data', doc)
    if d.get('lastName') == 'Oduya' and d.get('firstName') == 'Samuel':
        print(row['id'] + '|' + doc.get('_rev',''))
" 2>/dev/null || echo "")

if [ -n "$EXISTING" ]; then
    echo "$EXISTING" | while IFS='|' read -r doc_id rev; do
        if [ -n "$doc_id" ] && [ -n "$rev" ]; then
            curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null || true
            echo "Deleted existing patient record: $doc_id"
        fi
    done
fi

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready with HospitalRun..."
ensure_hospitalrun_logged_in

# Wait for PouchDB database to connect and patient list to load
wait_for_db_ready

# Navigate to new patient form (DB is now ready, form renders immediately)
echo "Navigating to Add New Patient page..."
navigate_firefox_to "http://localhost:3000/#/patients/new"
sleep 20  # Wait for Ember.js route to render the new patient form (mainDB already set)

# Take screenshot to show initial state
take_screenshot /tmp/register_patient_initial.png
echo "Task start state screenshot saved to /tmp/register_patient_initial.png"

echo "=== register_patient task setup complete ==="
echo "Agent should see: HospitalRun new patient registration form"
echo "Task: Fill in patient details for Samuel Oduya and save"
