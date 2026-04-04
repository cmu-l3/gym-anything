#!/bin/bash
set -e
echo "=== Setting up fulfill_inventory_request task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is accessible
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    if curl -s http://localhost:3000/ >/dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Fix offline sync issues (Critical for HospitalRun env)
# This ensures PouchDB can sync with CouchDB
fix_offline_sync

# 3. Clean up previous data (Idempotency)
echo "Cleaning up previous test data..."
hr_couch_delete "inventory_p1_gauze4x4"
hr_couch_delete "inv-request_p1_req001"

# 4. Seed Inventory Item
echo "Seeding Inventory Item..."
# HospitalRun expects data wrapped in a 'data' object
ITEM_JSON='{
  "data": {
    "friendlyId": "SUP001",
    "name": "Sterile Gauze Pads 4x4",
    "description": "4x4 sterile gauze sponges, 50/box",
    "quantity": 500,
    "inventoryType": "Supplies",
    "distributionUnit": "box",
    "crossReference": "SUP-GAUZE-4X4",
    "reorderPoint": 100,
    "status": "Active"
  }
}'
hr_couch_put "inventory_p1_gauze4x4" "$ITEM_JSON"

# 5. Seed Inventory Request
echo "Seeding Inventory Request..."
REQUEST_JSON='{
  "data": {
    "friendlyId": "REQ001",
    "inventoryItem": "inventory_p1_gauze4x4",
    "quantity": 50,
    "status": "Requested",
    "dateRequested": "2023-10-25T09:00:00.000Z",
    "dateNeeded": "2023-10-26T09:00:00.000Z",
    "requestedBy": "hradmin",
    "deliveryLocation": "Emergency Department",
    "reason": "Restock for weekend"
  }
}'
hr_couch_put "inv-request_p1_req001" "$REQUEST_JSON"

# 6. Record initial revision for anti-gaming check
# We capture the _rev of the request to ensure it changes
REQUEST_REV=$(hr_couch_get "inv-request_p1_req001" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$REQUEST_REV" > /tmp/initial_request_rev.txt
echo "Initial Request Rev: $REQUEST_REV"

# 7. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Navigate specifically to Inventory section to help load the module, 
# but let agent do the specific work of finding the request.
# Note: We navigate to the root or dashboard to ensure a clean state, 
# but for stability, loading the app root is safest.
navigate_firefox_to "http://localhost:3000/"
wait_for_db_ready

# 8. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured"

echo "=== Task setup complete ==="