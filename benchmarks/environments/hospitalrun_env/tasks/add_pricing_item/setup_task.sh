#!/bin/bash
echo "=== Setting up add_pricing_item task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 2. Verify HospitalRun and CouchDB are running
echo "Checking HospitalRun availability..."
wait_for_hospitalrun 30

# 3. Fix offline sync (CRITICAL for HospitalRun to work properly in this env)
fix_offline_sync

# 4. Clean up any previous attempts (idempotency)
echo "Cleaning up any existing pricing items with the target name..."
# Find docs with type 'pricing' and name 'Portable Ultrasound - Limited Bedside'
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc) # Handle nested or flat structure
    if d.get('name') == 'Portable Ultrasound - Limited Bedside':
        print(row['id'] + ' ' + doc.get('_rev',''))
" | while read -r doc_id rev; do
    if [ -n "$doc_id" ]; then
        echo "Deleting existing doc: $doc_id"
        curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null
    fi
done

# 5. Record initial count of pricing items (for anti-gaming)
echo "Recording initial pricing item count..."
INITIAL_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    # Check for pricing type - HospitalRun usually uses type='pricing'
    if d.get('type') == 'pricing' or doc.get('type') == 'pricing':
        count += 1
print(count)
" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_pricing_count.txt
echo "Initial pricing items: $INITIAL_COUNT"

# 6. Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 7. Wait for PouchDB to sync/connect
wait_for_db_ready

# 8. Navigate to Pricing section explicitly to help the agent get started? 
# No, let the agent find it. Just go to home.
navigate_firefox_to "http://localhost:3000"

# 9. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="