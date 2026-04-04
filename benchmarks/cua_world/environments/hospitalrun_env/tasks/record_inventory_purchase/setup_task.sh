#!/bin/bash
set -e
echo "=== Setting up record_inventory_purchase task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Setup Data: Seed the Inventory Item
# ID: inventory_p1_GLVLG001
# Name: Disposable Surgical Gloves - Large
# Qty: 200
echo "Seeding inventory item..."

ITEM_ID="inventory_p1_GLVLG001"
ITEM_DOC='{
  "data": {
    "friendlyId": "GLV-LG-001",
    "name": "Disposable Surgical Gloves - Large",
    "inventoryType": "Supplies",
    "distributionUnit": "Box",
    "quantity": 200,
    "crossReference": "GLV-LG-001",
    "status": "Active",
    "description": "Latex-free, powder-free surgical gloves, size Large",
    "reorderPoint": 50
  }
}'

# Delete existing if present to ensure clean state
REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${ITEM_ID}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))" 2>/dev/null || echo "")
if [ -n "$REV" ]; then
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${ITEM_ID}?rev=${REV}" > /dev/null
    echo "Removed existing item."
fi

# Create new item
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${ITEM_ID}" \
    -H "Content-Type: application/json" \
    -d "$ITEM_DOC" > /dev/null
echo "Seeded item: $ITEM_ID with quantity 200"

# 3. Ensure Firefox is ready and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 4. Wait for PouchDB sync
wait_for_db_ready

# 5. Navigate to Inventory list to start
echo "Navigating to Inventory page..."
navigate_firefox_to "http://localhost:3000/#/inventory"
sleep 15

# 6. Capture initial state
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="