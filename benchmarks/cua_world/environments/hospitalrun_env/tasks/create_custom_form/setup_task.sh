#!/bin/bash
echo "=== Setting up create_custom_form task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
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

# Clean up any existing "Fall Risk Assessment" forms to ensure a fresh start
echo "Checking for existing custom forms..."
# Custom forms usually have type 'custom_form' or similar. We scan all docs.
EXISTING_DOCS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    # Check for name 'Fall Risk Assessment'
    if doc.get('name') == 'Fall Risk Assessment':
        print(row['id'] + '|' + doc.get('_rev',''))
" 2>/dev/null || echo "")

if [ -n "$EXISTING_DOCS" ]; then
    echo "$EXISTING_DOCS" | while IFS='|' read -r doc_id rev; do
        if [ -n "$doc_id" ] && [ -n "$rev" ]; then
            echo "Deleting existing form: $doc_id"
            curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null || true
        fi
    done
else
    echo "No existing form found."
fi

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for PouchDB database to connect
wait_for_db_ready

# Navigate to Administration page as starting point
echo "Navigating to Administration..."
navigate_firefox_to "http://localhost:3000/#/admin"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== create_custom_form task setup complete ==="