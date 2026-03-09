#!/bin/bash
echo "=== Setting up update_inventory_request_quantity task ==="

source /workspace/scripts/task_utils.sh

# 1. Verify HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Fix PouchDB sync issues (standard fix for this env)
fix_offline_sync

# 3. Seed Data: Inventory Item "Surgical Masks"
# We force a specific ID so we can link to it easily
ITEM_ID="inv_item_masks_001"
ITEM_DOC='{
  "type": "inventory",
  "data": {
    "friendlyId": "INV001",
    "name": "Surgical Masks",
    "description": "Standard 3-ply surgical masks",
    "price": 0.5,
    "quantity": 5000,
    "crossDocking": false,
    "status": "Active",
    "distributionUnit": "Box of 50"
  }
}'

echo "Seeding Inventory Item..."
# Delete if exists
hr_couch_delete "$ITEM_ID"
# Create new
hr_couch_put "$ITEM_ID" "$ITEM_DOC"

# 4. Seed Data: Inventory Request for 100 units
REQ_ID="inv_req_masks_001"
REQ_DOC='{
  "type": "inventory_request",
  "data": {
    "inventoryItem": "inv_item_masks_001",
    "quantity": 100,
    "status": "Requested",
    "date": "2025-10-15T09:00:00.000Z",
    "reason": "Routine restocking"
  }
}'

echo "Seeding Inventory Request..."
# Delete if exists
hr_couch_delete "$REQ_ID"
# Create new
hr_couch_put "$REQ_ID" "$REQ_DOC"

# 5. Record Initial State (Revision ID)
# We need the _rev to prove the agent actually updated the doc
INITIAL_REV=$(hr_couch_get "$REQ_ID" | python3 -c "import sys,json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$INITIAL_REV" > /tmp/initial_req_rev.txt
echo "Initial Request Revision: $INITIAL_REV"

# 6. Browser Setup
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Navigate specifically to Inventory Requests to help the agent start (optional, but helpful)
# The URL for requests list in HospitalRun is usually #/inventory/requests or similar
navigate_firefox_to "http://localhost:3000/#/inventory/requests"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Task setup complete"