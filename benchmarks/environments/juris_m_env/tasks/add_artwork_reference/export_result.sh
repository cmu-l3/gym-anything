#!/bin/bash
echo "=== Exporting add_artwork_reference result ==="
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find Jurism database
JURISM_DB=$(get_jurism_db)

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism database not found"
    # Create empty result
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# Use Python to robustly query the SQLite EAV structure
# We extract the most likely candidate item and its details
python3 -c "
import sqlite3
import json
import os
from datetime import datetime

db_path = '$JURISM_DB'
task_start = $TASK_START
target_title = 'The Problem We All Live With'

result = {
    'task_start': task_start,
    'task_end': $TASK_END,
    'item_found': False,
    'item_details': {},
    'error': None
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Find the item by title
    # We look for the most recently added item with the matching title
    c.execute('''
        SELECT items.itemID, items.dateAdded, itemTypes.typeName 
        FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        JOIN fields ON itemData.fieldID = fields.fieldID
        JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID
        WHERE fields.fieldName = 'title' 
          AND LOWER(itemDataValues.value) = LOWER(?)
          AND items.itemTypeID NOT IN (1, 14) -- Exclude attachments/notes
        ORDER BY items.dateAdded DESC LIMIT 1
    ''', (target_title,))
    
    row = c.fetchone()
    
    if row:
        item_id = row['itemID']
        date_added_str = row['dateAdded']
        
        # Convert DB timestamp to unix for comparison
        # DB format is usually 'YYYY-MM-DD HH:MM:SS'
        try:
            dt = datetime.strptime(date_added_str, '%Y-%m-%d %H:%M:%S')
            date_added_ts = dt.timestamp()
        except:
            date_added_ts = 0

        result['item_found'] = True
        result['item_details'] = {
            'itemID': item_id,
            'typeName': row['typeName'],
            'dateAdded': date_added_str,
            'created_after_start': date_added_ts > task_start,
            'fields': {},
            'creators': []
        }
        
        # 2. Get all metadata fields for this item
        c.execute('''
            SELECT fields.fieldName, itemDataValues.value 
            FROM itemData 
            JOIN fields ON itemData.fieldID = fields.fieldID
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            WHERE itemData.itemID = ?
        ''', (item_id,))
        
        for field in c.fetchall():
            result['item_details']['fields'][field['fieldName']] = field['value']
            
        # 3. Get creators
        c.execute('''
            SELECT creators.firstName, creators.lastName, creatorTypes.creatorType 
            FROM itemCreators 
            JOIN creators ON itemCreators.creatorID = creators.creatorID
            JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
            WHERE itemCreators.itemID = ?
            ORDER BY itemCreators.orderIndex
        ''', (item_id,))
        
        for creator in c.fetchall():
            result['item_details']['creators'].append({
                'firstName': creator['firstName'],
                'lastName': creator['lastName'],
                'creatorType': creator['creatorType']
            })

    conn.close()

except Exception as e:
    result['error'] = str(e)

# Write result to temp file then move
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Move result to final location with permissive permissions
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="