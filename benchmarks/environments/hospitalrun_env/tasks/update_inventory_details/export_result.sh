#!/bin/bash
echo "=== Exporting update_inventory_details result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the item "Surgical Face Masks" and export to JSON
# We include the _rev string to help debug if needed, but mostly we want the fields.
python3 -c "
import sys, json, requests, time

couch_url = '${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}'
item_name = 'Surgical Face Masks'

result = {
    'item_found': False,
    'location': None,
    'price': None,
    'last_updated': 0,
    'doc_rev': None
}

try:
    resp = requests.get(f'{couch_url}/_all_docs?include_docs=true')
    data = resp.json()
    
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        d = doc.get('data', doc)
        
        if d.get('type') == 'inventory' and d.get('name') == item_name:
            result['item_found'] = True
            result['location'] = d.get('location')
            result['price'] = d.get('price')
            result['doc_rev'] = doc.get('_rev')
            
            # Try to infer modification time. 
            # CouchDB doesn't always store mod time in doc unless app does.
            # HospitalRun often adds 'audit' info.
            # If not present, we rely on value changes in verification.
            audit = d.get('audit', {})
            # This is just a guess at schema, verification will primarily use values
            break
            
except Exception as e:
    result['error'] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so the host can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json