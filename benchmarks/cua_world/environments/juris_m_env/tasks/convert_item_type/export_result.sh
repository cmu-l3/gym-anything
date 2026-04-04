#!/bin/bash
echo "=== Exporting convert_item_type Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/convert_final.png

# Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JURISM_DB=$(get_jurism_db)

if [ -z "$JURISM_DB" ]; then
    echo '{"error": "Jurism database not found"}' > /tmp/task_result.json
    exit 1
fi

# Python script to query the database and extract item status
python3 -c "
import sqlite3
import json
import os
from datetime import datetime

db_path = '$JURISM_DB'
task_start_ts = int($TASK_START)

result = {
    'item_found': False,
    'item_type_id': None,
    'fields': {},
    'date_added_ts': 0,
    'date_modified_ts': 0,
    'is_original_item': False,
    'was_modified_after_start': False
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Find item with 'Roe v. Wade' in Title (1) or Case Name (58)
    # The user might have changed the type, so the field ID for the name might be 58 now.
    query = '''
        SELECT items.itemID, items.itemTypeID, items.dateAdded, items.dateModified
        FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE (itemData.fieldID = 1 OR itemData.fieldID = 58) 
          AND LOWER(itemDataValues.value) = 'roe v. wade'
        LIMIT 1
    '''
    c.execute(query)
    row = c.fetchone()
    
    if row:
        item_id, type_id, date_added, date_modified = row
        result['item_found'] = True
        result['item_type_id'] = type_id
        
        # Parse timestamps (Format: YYYY-MM-DD HH:MM:SS)
        # Handle potential timezone offsets or string formats
        try:
            da_dt = datetime.strptime(date_added, '%Y-%m-%d %H:%M:%S')
            dm_dt = datetime.strptime(date_modified, '%Y-%m-%d %H:%M:%S')
            result['date_added_ts'] = da_dt.timestamp()
            result['date_modified_ts'] = dm_dt.timestamp()
            
            # Anti-gaming checks
            # 1. Did this item exist BEFORE task start? (Should be yes - we injected it)
            if result['date_added_ts'] < task_start_ts:
                result['is_original_item'] = True
            
            # 2. Was it modified AFTER task start?
            if result['date_modified_ts'] > task_start_ts:
                result['was_modified_after_start'] = True
        except ValueError:
            pass # Keep defaults if date parse fails

        # Extract all fields for this item
        c.execute('''
            SELECT fieldID, value 
            FROM itemData 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE itemID = ?
        ''', (item_id,))
        
        # Map field IDs to names for easier verification
        # 58: caseName, 60: court, 66: reporterVolume, 49: reporter, 67: firstPage, 69: dateDecided
        field_map = {
            1: 'title',
            58: 'caseName',
            60: 'court',
            66: 'volume',
            49: 'reporter',
            67: 'firstPage',
            69: 'dateDecided',
            8: 'date' # Journal date
        }
        
        for fid, val in c.fetchall():
            fname = field_map.get(fid, f'field_{fid}')
            result['fields'][fname] = val

    conn.close()

except Exception as e:
    result['error'] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Add screenshot info
# Use jq or python to append screenshot path safely? 
# Simpler: just ensure file exists, verifier checks file presence.
# But let's follow pattern and keep JSON valid.
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        d = json.load(f)
    d['screenshot_path'] = '/tmp/convert_final.png'
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(d, f, indent=4)
except: pass
"

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="