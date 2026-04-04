#!/bin/bash
set -e
echo "=== Setting up add_item_to_purchase_order task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Fix Offline Sync / PouchDB loading issues FIRST
# This ensures the DB is writable and the app loads correctly
fix_offline_sync

# 2. Seed Inventory Items
echo "Seeding inventory items..."

# Item 1: Surgical Gowns
GOWN_DOC='{
  "name": "Surgical Gowns",
  "friendlyId": "SURG-001",
  "description": "Sterile surgical gowns, size L",
  "price": 5.00,
  "quantity": 100,
  "docType": "inventory",
  "crossReference": [],
  "type": "inventory"
}'
# Post and capture ID
hr_couch_post "$GOWN_DOC" > /tmp/gown_res.txt
GOWN_ID=$(cat /tmp/gown_res.txt | python3 -c "import sys,json; print(json.load(sys.stdin).get('id'))")

# Item 2: N95 Respirator (The item to be added)
MASK_DOC='{
  "name": "N95 Respirator",
  "friendlyId": "RESP-95",
  "description": "NIOSH-approved N95 particulate respirator",
  "price": 1.50,
  "quantity": 500,
  "docType": "inventory",
  "crossReference": [],
  "type": "inventory"
}'
hr_couch_post "$MASK_DOC" > /tmp/mask_res.txt
MASK_ID=$(cat /tmp/mask_res.txt | python3 -c "import sys,json; print(json.load(sys.stdin).get('id'))")

echo "Created items: Gowns ($GOWN_ID), Masks ($MASK_ID)"

# 3. Create the Pending Purchase Order
echo "Creating pending purchase order..."
# Note: HospitalRun requires specific structure for items
PO_DOC=$(cat <<EOF
{
  "vendor": "Global Health Supplies",
  "status": "Pending",
  "date": "$(date +%Y-%m-%dT%H:%M:%S.000Z)",
  "dateReceived": null,
  "items": [
    {
      "name": "Surgical Gowns",
      "quantity": 100,
      "unitPrice": 5.00,
      "inventoryItem": "${GOWN_ID}"
    }
  ],
  "docType": "purchase_order",
  "type": "purchase_order"
}
EOF
)

hr_couch_post "$PO_DOC" > /tmp/po_res.txt
PO_ID=$(cat /tmp/po_res.txt | python3 -c "import sys,json; print(json.load(sys.stdin).get('id'))")
INITIAL_REV=$(cat /tmp/po_res.txt | python3 -c "import sys,json; print(json.load(sys.stdin).get('rev'))")

echo "Created Purchase Order ID: $PO_ID"
echo "$PO_ID" > /tmp/target_po_id.txt
echo "$INITIAL_REV" > /tmp/initial_po_rev.txt

# 4. Launch Firefox directly to the Edit page for this PO
# This saves the agent from having to search for it, focusing on the editing task
TARGET_URL="${HR_URL}/#/inventory/purchase-orders/edit/${PO_ID}"
echo "Navigating to $TARGET_URL"

# Ensure Firefox is clean
pkill -f firefox || true
sleep 1

# Launch Firefox
DISPLAY=:1 firefox --new-window "$TARGET_URL" &

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Wait for page load (Ember app takes a moment)
sleep 15

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="