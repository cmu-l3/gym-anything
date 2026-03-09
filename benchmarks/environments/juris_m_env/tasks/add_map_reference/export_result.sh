#!/bin/bash
echo "=== Exporting add_map_reference Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/map_task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
JURISM_DB=$(get_jurism_db)

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# We use a Python script to query the DB robustly using join logic for field names
# This avoids hardcoding fieldIDs which might vary between versions
python3 -c "
import sqlite3
import json
import os
import sys

db_path = '$JURISM_DB'
task_start = $TASK_START
result = {
    'task_start': task_start,
    'task_end': $TASK_END,
    'item_found': False,
    'fields': {},
    'creator': {},
    'created_during_task': False
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Find the Map item type ID
    c.execute(\"SELECT itemTypeID FROM itemTypes WHERE typeName='map'\")
    row = c.fetchone()
    map_type_id = row[0] if row else 12  # Default to 12 if lookup fails

    # 2. Find items of type Map created/modified recently or matching title
    # We look for the specific title first
    c.execute('''
        SELECT items.itemID, items.dateAdded 
        FROM items
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        JOIN fields ON itemData.fieldID = fields.fieldID
        WHERE items.itemTypeID = ? 
        AND fields.fieldName = 'title' 
        AND itemDataValues.value LIKE '%Washington West%'
        LIMIT 1
    ''', (map_type_id,))
    
    item_row = c.fetchone()
    
    if item_row:
        result['item_found'] = True
        item_id = item_row['itemID']
        date_added = item_row['dateAdded']
        
        # Check timestamp (basic string comparison or check if it exists)
        # Jurism stores dates as 'YYYY-MM-DD HH:MM:SS', we trust the existence check mostly
        # but verification logic in python handles strict timestamp checks if needed.
        # Here we just flag if it was likely created in this session.
        result['item_id'] = item_id
        
        # Get all fields
        c.execute('''
            SELECT fields.fieldName, itemDataValues.value 
            FROM itemData 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            JOIN fields ON itemData.fieldID = fields.fieldID
            WHERE itemData.itemID = ?
        ''', (item_id,))
        
        for row in c.fetchall():
            result['fields'][row['fieldName']] = row['value']

        # Get creators
        c.execute('''
            SELECT creators.firstName, creators.lastName, creatorTypes.creatorType 
            FROM itemCreators
            JOIN creators ON itemCreators.creatorID = creators.creatorID
            JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
            WHERE itemCreators.itemID = ?
            ORDER BY itemCreators.orderIndex
        ''', (item_id,))
        
        creators = []
        for row in c.fetchall():
            creators.append({
                'firstName': row['firstName'],
                'lastName': row['lastName'],
                'type': row['creatorType']
            })
        result['creators'] = creators

        # Anti-gaming: Check if modification date is recent
        # We rely on the Verifier to do strict time comparison if needed, 
        # but here we can pass the raw date string
        result['date_added_str'] = date_added

except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permission for result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="