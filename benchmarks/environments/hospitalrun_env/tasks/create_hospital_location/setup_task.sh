#!/bin/bash
echo "=== Setting up create_hospital_location task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

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

# Clean up any existing location with the target name (for idempotency)
echo "Cleaning up any existing 'Cardiology Outpatient Center' records..."
EXISTING=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    # Check common name fields
    name = d.get('name', d.get('value', ''))
    if name == 'Cardiology Outpatient Center':
        print(row['id'] + '|' + doc.get('_rev',''))
" 2>/dev/null || echo "")

if [ -n "$EXISTING" ]; then
    echo "$EXISTING" | while IFS='|' read -r doc_id rev; do
        if [ -n "$doc_id" ] && [ -n "$rev" ]; then
            curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null || true
            echo "Deleted existing location record: $doc_id"
        fi
    done
fi

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for PouchDB database to connect
wait_for_db_ready

# Navigate to the Administration or Dashboard page to start
navigate_firefox_to "http://localhost:3000"

# Take initial screenshot
take_screenshot /tmp/create_location_initial.png
echo "Task start state screenshot saved to /tmp/create_location_initial.png"

echo "=== create_hospital_location task setup complete ==="
echo "Agent should see: HospitalRun Dashboard"
echo "Task: Navigate to Admin/Lookups and create 'Cardiology Outpatient Center'"