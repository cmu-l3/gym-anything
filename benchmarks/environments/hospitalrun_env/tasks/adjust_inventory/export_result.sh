#!/bin/bash
echo "=== Exporting adjust_inventory results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch all documents from CouchDB with include_docs
# We will process them in Python to find the new adjustment
echo "Fetching database state..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/all_docs.json

# 3. Prepare Result JSON using Python for robustness
# We filter for documents created/modified after task start that look like inventory adjustments
python3 -c "
import json
import os
import sys

try:
    task_start = int(os.environ.get('TASK_START', 0))
    
    # Load initial IDs to identify NEW documents
    initial_ids = set()
    if os.path.exists('/tmp/initial_doc_ids.txt'):
        with open('/tmp/initial_doc_ids.txt', 'r') as f:
            initial_ids = set(line.strip() for line in f if line.strip())

    with open('/tmp/all_docs.json', 'r') as f:
        data = json.load(f)

    rows = data.get('rows', [])
    
    inventory_item = None
    adjustments = []
    
    for row in rows:
        doc = row.get('doc', {})
        doc_id = doc.get('_id', '')
        
        # Check if this is our target item
        if doc_id == 'inventory_p1_amox500':
            inventory_item = doc.get('data', doc)
            continue
            
        # Check if this is a NEW document (not in initial list)
        if doc_id not in initial_ids:
            # Look for adjustment characteristics
            # HospitalRun often uses type: 'inventory_transfer' or similar for adjustments
            # Or checks for 'transactionType' fields
            d = doc.get('data', doc)
            doc_str = json.dumps(doc).lower()
            
            # Heuristic for adjustment doc
            if 'amoxicillin' in doc_str or 'inv001' in doc_str:
                adjustments.append({
                    'id': doc_id,
                    'content': d
                })

    result = {
        'task_start': task_start,
        'item_state': inventory_item,
        'new_adjustments': adjustments,
        'screenshot_exists': os.path.exists('/tmp/task_final.png')
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
    print(f'Exported {len(adjustments)} potential adjustment documents')

except Exception as e:
    print(f'Error exporting: {e}')
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# 4. Secure output
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="