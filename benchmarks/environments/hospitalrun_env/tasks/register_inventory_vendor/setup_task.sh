#!/bin/bash
set -e
echo "=== Setting up register_inventory_vendor task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing vendor with this name to ensure the agent actually creates it
echo "Cleaning up stale vendor data..."
# Query CouchDB for 'Global Pharma Supplies'
STALE_DOCS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        # Check top level or data wrapper
        d = doc.get('data', doc)
        name = d.get('name', '') or d.get('vendorName', '')
        if 'Global Pharma Supplies' in name:
            print(f\"{doc['_id']} {doc.get('_rev', '')}\")
except:
    pass
")

# Delete found docs
if [ -n "$STALE_DOCS" ]; then
    echo "$STALE_DOCS" | while read -r doc_id rev; do
        if [ -n "$doc_id" ]; then
            echo "Deleting stale doc: $doc_id"
            curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null
        fi
    done
else
    echo "No stale data found."
fi

# 2. Ensure HospitalRun is running
echo "Checking HospitalRun status..."
for i in {1..30}; do
    if curl -s http://localhost:3000 >/dev/null; then
        echo "HospitalRun is up."
        break
    fi
    sleep 1
done

# 3. Fix offline sync issues (PouchDB loading bug)
fix_offline_sync

# 4. Launch Firefox and Login
echo "Launching Firefox..."
# We use the helper from task_utils to ensure clean state and login
ensure_hospitalrun_logged_in

# 5. Navigate to Inventory Dashboard to give agent a head start
echo "Navigating to Inventory..."
navigate_firefox_to "http://localhost:3000/#/inventory"
sleep 5

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="