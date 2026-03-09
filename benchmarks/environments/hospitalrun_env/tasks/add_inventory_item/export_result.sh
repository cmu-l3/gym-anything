#!/bin/bash
echo "=== Exporting add_inventory_item result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_inventory_count.txt 2>/dev/null || echo "0")

# 3. Query CouchDB for the specific item
echo "Searching CouchDB for 'BD Vacutainer SST Tubes'..."

# We fetch all docs and filter in Python to handle the flexible schema of HospitalRun
# (It wraps data in a 'data' property, sometimes fields are top-level depending on version/adapter)
RESULT_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
    python3 -c "
import sys, json, time

task_start = $TASK_START
target_name = 'bd vacutainer sst tubes'

try:
    data = json.load(sys.stdin)
    rows = data.get('rows', [])
    
    # Calculate current inventory count
    current_count = len([r for r in rows if 'inventory' in r.get('doc', {}).get('type', '') or 'inventory' in r.get('id', '')])
    
    found_item = None
    
    for row in rows:
        doc = row.get('doc', {})
        d = doc.get('data', doc) # Handle nested data wrapper
        
        name = d.get('name', d.get('friendlyName', ''))
        
        if target_name.lower() in str(name).lower():
            found_item = d
            # Add metadata from the wrapper doc
            found_item['_id'] = doc.get('_id')
            found_item['_rev'] = doc.get('_rev')
            break
            
    output = {
        'task_start': task_start,
        'initial_count': int('$INITIAL_COUNT'),
        'current_count': current_count,
        'item_found': found_item is not None,
        'item_data': found_item if found_item else {},
        'timestamp': time.time()
    }
    print(json.dumps(output))
except Exception as e:
    print(json.dumps({'error': str(e), 'item_found': False}))
")

# 4. Save result to file
echo "$RESULT_JSON" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json