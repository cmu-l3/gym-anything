#!/bin/bash
set -e
echo "=== Setting up update_inventory_reorder_point task ==="

# Define configuration
HR_COUCH_URL="http://couchadmin:test@localhost:5984"
HR_COUCH_MAIN_DB="main"
MOUNTED_UTILS="/workspace/scripts/task_utils.sh"

# Load shared utilities if available
if [ -f "$MOUNTED_UTILS" ]; then
    source "$MOUNTED_UTILS"
else
    echo "Warning: task_utils.sh not found, using local definitions"
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is accessible
echo "Waiting for HospitalRun..."
for i in {1..30}; do
    if curl -s http://localhost:3000 >/dev/null; then
        echo "HospitalRun is up."
        break
    fi
    sleep 2
done

# 2. Fix PouchDB Sync (Critical for app functionality)
# Use utility function if available, otherwise inline critical fix
if type fix_offline_sync &>/dev/null; then
    fix_offline_sync
else
    echo "Applying minimal PouchDB fix..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_security" \
        -H "Content-Type: application/json" -d '{}' || true
fi

# 3. Seed the Inventory Item
echo "Seeding 'Amoxicillin 500mg'..."

# Search for existing item to get ID/Rev
EXISTING_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        # HospitalRun wraps content in 'data', but we check top level too just in case
        name = doc.get('name') or doc.get('data', {}).get('name')
        if name == 'Amoxicillin 500mg':
            print(json.dumps({'id': doc['_id'], 'rev': doc['_rev']}))
            break
except:
    pass
")

# Define the item state we want (Reorder: 50, Price: 10.00)
# HospitalRun requires data to be wrapped in a 'data' property for the UI to read it correctly,
# but also indexes top-level properties for PouchDB. We duplicate to be safe.
ITEM_JSON='{
    "type": "inventory",
    "name": "Amoxicillin 500mg",
    "friendlyId": "INV-AMOX-500",
    "description": "Amoxicillin 500mg Capsules, Bottle of 100",
    "price": 10.00,
    "quantity": 400,
    "reorderPoint": 50,
    "distributionUnit": "Bottle",
    "status": "Available",
    "crossReference": "RX-AMOX-001",
    "data": {
        "type": "inventory",
        "name": "Amoxicillin 500mg",
        "friendlyId": "INV-AMOX-500",
        "description": "Amoxicillin 500mg Capsules, Bottle of 100",
        "price": 10.00,
        "quantity": 400,
        "reorderPoint": 50,
        "distributionUnit": "Bottle",
        "status": "Available",
        "crossReference": "RX-AMOX-001"
    }
}'

if [ -n "$EXISTING_DOC" ]; then
    DOC_ID=$(echo "$EXISTING_DOC" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
    DOC_REV=$(echo "$EXISTING_DOC" | python3 -c "import sys, json; print(json.load(sys.stdin)['rev'])")
    
    echo "Updating existing item ($DOC_ID)..."
    # Merge _id and _rev into the JSON
    FULL_JSON=$(echo "$ITEM_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['_id'] = '$DOC_ID'
d['_rev'] = '$DOC_REV'
print(json.dumps(d))
")
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${DOC_ID}" \
        -H "Content-Type: application/json" -d "$FULL_JSON" > /dev/null
else
    echo "Creating new item..."
    # Create ID
    NEW_ID="inventory_$(date +%s)_amox"
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${NEW_ID}" \
        -H "Content-Type: application/json" -d "$ITEM_JSON" > /dev/null
fi

# 4. Prepare Browser
echo "Launching Firefox..."
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox http://localhost:3000 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
        echo "Firefox detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Ensure login (if utility available)
if type ensure_hospitalrun_logged_in &>/dev/null; then
    ensure_hospitalrun_logged_in
fi

# 5. Capture Initial State
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="