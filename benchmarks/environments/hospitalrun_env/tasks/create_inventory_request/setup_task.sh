#!/bin/bash
set -e
echo "=== Setting up Create Inventory Request task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── Ensure HospitalRun services are running ────────────────────────────────
echo "[setup] Checking HospitalRun services..."
cd /home/ga/hospitalrun

# Start services if not running
docker compose up -d 2>/dev/null || true

# Wait for CouchDB
echo "[setup] Waiting for CouchDB..."
for i in $(seq 1 30); do
    if curl -s http://localhost:5984/ | grep -q "couchdb"; then
        echo "CouchDB is ready"
        break
    fi
    sleep 2
done

# Wait for HospitalRun app
echo "[setup] Waiting for HospitalRun..."
for i in $(seq 1 40); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is ready"
        break
    fi
    sleep 3
done

# ─── Verify Sterile Gauze Pads inventory item exists ─────────────────────────
echo "[setup] Verifying gauze pads inventory item exists..."
COUCH_URL="http://couchadmin:test@localhost:5984"

# Check if the item exists
GAUZE_EXISTS=$(curl -s "${COUCH_URL}/main/_all_docs?include_docs=true" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    found = False
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        d = doc.get('data', doc)
        name = d.get('name', '') or d.get('friendlyId', '')
        if 'Sterile Gauze Pads' in name:
            found = True
            break
    print('found' if found else 'not_found')
except:
    print('error')
" 2>/dev/null || echo "error")

if [ "$GAUZE_EXISTS" != "found" ]; then
    echo "[setup] Gauze Pads not found, seeding item..."
    # Seed the item
    ITEM_DOC=$(cat <<'ENDDOC'
{
    "_id": "inventory_p1_gauze001",
    "data": {
        "name": "Sterile Gauze Pads (4x4 inch)",
        "quantity": 150,
        "crossReference": "GAU-44-ST",
        "inventoryType": "Supplies",
        "reorderPoint": 50,
        "distributionUnit": "box",
        "price": 8.50,
        "friendlyId": "P100005",
        "status": "Active"
    },
    "type": "inventory"
}
ENDDOC
    )
    # Try with auth
    curl -s -X PUT "${COUCH_URL}/main/inventory_p1_gauze001" \
        -H "Content-Type: application/json" \
        -d "$ITEM_DOC" >/dev/null || true
    echo "[setup] Seeded Sterile Gauze Pads item"
fi

# ─── Record initial inventory request count ──────────────────────────────────
echo "[setup] Recording initial inventory request count..."
INITIAL_COUNT=$(curl -s "${COUCH_URL}/main/_all_docs?include_docs=true" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    count = 0
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        d = doc.get('data', doc)
        doc_type = d.get('type', doc.get('type', ''))
        # Check for inventory request type
        if doc_type == 'inventory_request' or doc_type == 'inventoryRequest' or 'inv-request' in row['id']:
            count += 1
    print(count)
except:
    print(0)
" 2>/dev/null || echo "0")

echo "$INITIAL_COUNT" > /tmp/initial_inv_request_count.txt
echo "[setup] Initial inventory request count: $INITIAL_COUNT"

# ─── Ensure Firefox is fresh and logged in ──────────────────────────────────
# Use shared helper to fix PouchDB sync issues and log in
fix_offline_sync
ensure_hospitalrun_logged_in

# Navigate to Inventory section to help agent start close to context (optional, but helpful)
# But description says "Navigate to the Inventory section...", so we start at dashboard/home.
navigate_firefox_to "http://localhost:3000"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="