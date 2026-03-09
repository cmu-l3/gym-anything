#!/bin/bash
set -e
echo "=== Setting up adjust_inventory task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure HospitalRun services are up
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Fix PouchDB/Offline Sync issues (Critical for app functionality)
fix_offline_sync

# 3. Seed/Reset the specific Inventory Item
echo "Seeding Inventory Item: Amoxicillin 500mg Capsules..."
# We use a specific ID so we can track it easily
ITEM_ID="inventory_p1_amox500"
ITEM_DOC=$(cat <<EOF
{
  "data": {
    "friendlyId": "INV001",
    "name": "Amoxicillin 500mg Capsules",
    "description": "Antibiotic for bacterial infections",
    "price": 0.45,
    "quantity": 500,
    "status": "Active",
    "type": "Medication",
    "crossDocking": false,
    "location": "Pharmacy",
    "dateReceived": "$(date +%s%3N)"
  }
}
EOF
)

# Delete existing if present to ensure clean state
hr_couch_delete "$ITEM_ID" || true
sleep 1
# Create fresh item
hr_couch_put "$ITEM_ID" "$ITEM_DOC"
echo "Item seeded with Quantity: 500"

# 4. Record Initial State for Anti-Gaming
# Record start time (Unix timestamp)
date +%s > /tmp/task_start_time.txt

# Record list of all document IDs currently in DB
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs" \
    | python3 -c "import sys, json; print('\n'.join([r['id'] for r in json.load(sys.stdin).get('rows', [])]))" \
    > /tmp/initial_doc_ids.txt

# 5. Launch Application
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for DB sync in UI
wait_for_db_ready

# Navigate to Inventory list to save agent some clicks (optional, but helps stability)
navigate_firefox_to "http://localhost:3000/#/inventory"
sleep 5

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="