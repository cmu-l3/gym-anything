#!/bin/bash
echo "=== Setting up update_inventory_details task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for HospitalRun/CouchDB
echo "Checking HospitalRun availability..."
wait_for_db_ready

# 2. Ensure the specific inventory item exists with INITIAL values
# We search for it first to get its ID if it exists
ITEM_NAME="Surgical Face Masks"
INITIAL_LOC="Central Warehouse"
INITIAL_PRICE="12.00"

echo "Configuring inventory item: $ITEM_NAME..."

# Helper python script to find/update/create the doc
python3 -c "
import sys, json, requests

couch_url = '${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}'
query_url = f'{couch_url}/_all_docs?include_docs=true'

try:
    # 1. Search for existing item
    resp = requests.get(query_url)
    data = resp.json()
    
    existing_doc = None
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        # Check wrapped data or top level
        d = doc.get('data', doc)
        # HospitalRun inventory items usually have type 'inventory'
        if d.get('type') == 'inventory' and d.get('name') == '$ITEM_NAME':
            existing_doc = doc
            break
    
    # 2. Prepare payload
    payload = {
        'name': '$ITEM_NAME',
        'friendlyId': 'INV001',
        'description': 'Standard 3-ply surgical masks',
        'price': $INITIAL_PRICE,
        'quantity': 500,
        'location': '$INITIAL_LOC',
        'type': 'inventory',
        'status': 'Active'
    }

    if existing_doc:
        print(f'Updating existing document: {existing_doc[\"_id\"]}')
        # Keep ID and Rev
        full_doc = existing_doc
        # Update content (HospitalRun puts fields in 'data' usually, but sometimes root for raw access)
        # We ensure 'data' wrapper exists if that's the schema
        if 'data' in full_doc:
            full_doc['data'].update(payload)
        else:
            full_doc['data'] = payload
            # Also update root keys if they exist to be safe
            for k, v in payload.items():
                if k in full_doc:
                    full_doc[k] = v
        
        r = requests.put(f'{couch_url}/{full_doc[\"_id\"]}', json=full_doc)
        print(f'Update status: {r.status_code}')
    else:
        print('Creating new document')
        # Create new ID
        new_id = 'inventory_inv001'
        new_doc = {
            '_id': new_id,
            'data': payload
        }
        r = requests.put(f'{couch_url}/{new_id}', json=new_doc)
        print(f'Create status: {r.status_code}')

except Exception as e:
    print(f'Error setting up data: {e}')
    sys.exit(1)
"

# 3. Ensure browser is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 4. Navigate to Inventory list to save agent some clicks (optional, but good for reliable start)
echo "Navigating to Inventory module..."
navigate_firefox_to "http://localhost:3000/#/inventory"
sleep 5

# 5. Capture initial state
take_screenshot /tmp/task_initial.png
echo "Setup complete."