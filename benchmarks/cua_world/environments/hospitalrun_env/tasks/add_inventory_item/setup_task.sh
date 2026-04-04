#!/bin/bash
set -e
echo "=== Setting up add_inventory_item task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 3. Clean up any existing inventory item with the target name (Idempotency)
echo "Cleaning up any previous 'BD Vacutainer SST Tubes'..."
EXISTING=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        d = doc.get('data', doc)
        # Check Name field (case-insensitive)
        name = d.get('name', d.get('friendlyName', '')).lower()
        if 'bd vacutainer sst tubes' in name:
            print(f\"{row['id']}|{doc.get('_rev','')}\")
except Exception:
    pass
" 2>/dev/null || echo "")

if [ -n "$EXISTING" ]; then
    echo "$EXISTING" | while IFS='|' read -r doc_id rev; do
        if [ -n "$doc_id" ] && [ -n "$rev" ]; then
            curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null || true
            echo "Deleted existing item: $doc_id"
        fi
    done
fi

# 4. Record initial inventory count
INITIAL_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
    python3 -c "import sys, json; print(len([r for r in json.load(sys.stdin).get('rows', []) if 'inventory' in r.get('doc', {}).get('type', '') or 'inventory' in r.get('id', '')]))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_inventory_count.txt

# 5. Prepare the browser environment
# Fix the offline sync issue to ensure PouchDB loads correctly
fix_offline_sync

# Ensure Firefox is open and logged in
ensure_hospitalrun_logged_in

# Navigate to the Inventory page to save the agent a step (optional, but good for starting state)
navigate_firefox_to "http://localhost:3000/#/inventory"

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="