#!/bin/bash
echo "=== Exporting Process Returned Mail Result ==="

source /workspace/scripts/task_utils.sh

# Load ground truth
GROUND_TRUTH_FILE="/tmp/npai_ground_truth.json"

if [ ! -f "$GROUND_TRUTH_FILE" ]; then
    echo "Error: Ground truth file missing."
    exit 1
fi

# Prepare result file
RESULT_FILE="/tmp/task_result.json"

# Helper to read JSON using python (since jq might not be available or minimal)
# We will construct the JSON manually or use python to query db and build it.

echo "Querying database for target statuses..."

# We need to verify 3 things for each target:
# 1. Has 'NPAI - ' prefix?
# 2. Contains original address?
# 3. Overall DB integrity.

# Use Python to do the complex logic and database querying to ensure robust JSON generation
python3 -c "
import json
import subprocess
import pymysql
import sys

def get_db_connection():
    return pymysql.connect(host='localhost', user='root', password='', database='DrTuxTest', charset='utf8mb4')

try:
    # Load ground truth
    with open('$GROUND_TRUTH_FILE', 'r') as f:
        targets = json.load(f)

    results = {
        'targets': [],
        'collateral_damage': False,
        'initial_npai_count': 0,
        'current_npai_count': 0
    }

    conn = get_db_connection()
    cursor = conn.cursor()

    # Check each target
    for target in targets:
        guid = target['guid']
        orig_addr = target['original_address']
        
        cursor.execute('SELECT FchPat_Adresse FROM fchpat WHERE FchPat_GUID_Doss = %s', (guid,))
        row = cursor.fetchone()
        
        target_res = {
            'guid': guid,
            'original': orig_addr,
            'current': '',
            'has_prefix': False,
            'preserves_data': False
        }
        
        if row:
            current_addr = row[0]
            target_res['current'] = current_addr
            
            # Check prefix (allow slight variations like 'NPAI-' or 'NPAI ')
            if current_addr.strip().upper().startswith('NPAI'):
                target_res['has_prefix'] = True
            
            # Check data preservation
            # Should contain the original address string (ignoring the prefix)
            # Simple check: is original address a substring of current?
            if orig_addr in current_addr:
                target_res['preserves_data'] = True
                
        results['targets'].append(target_res)

    # Check collateral damage
    # Get initial count
    try:
        with open('/tmp/initial_npai_count.txt', 'r') as f:
            initial_count = int(f.read().strip())
    except:
        initial_count = 0
        
    results['initial_npai_count'] = initial_count
    
    cursor.execute(\"SELECT COUNT(*) FROM fchpat WHERE FchPat_Adresse LIKE 'NPAI%'\")
    current_count = cursor.fetchone()[0]
    results['current_npai_count'] = current_count
    
    # We expect exactly 3 new NPAI records
    # If current > initial + 3, user modified others
    if current_count > (initial_count + 3):
        results['collateral_damage'] = True

    conn.close()

    # Write result
    with open('$RESULT_FILE', 'w') as f:
        json.dump(results, f, indent=2)

except Exception as e:
    print(f'Error in export script: {e}')
    sys.exit(1)
"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Append screenshot info to result (using sed/temp file to insert field)
# A bit hacky but avoids full python re-parse just for this
if [ -f /tmp/task_final.png ]; then
    # Use python to safely append
    python3 -c "
import json
try:
    with open('$RESULT_FILE', 'r') as f:
        d = json.load(f)
    d['screenshot_exists'] = True
    with open('$RESULT_FILE', 'w') as f:
        json.dump(d, f)
except: pass
"
fi

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="