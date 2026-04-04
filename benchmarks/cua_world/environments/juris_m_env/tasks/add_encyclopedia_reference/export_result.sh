#!/bin/bash
echo "=== Exporting add_encyclopedia_reference result ==="
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find database
JURISM_DB=$(get_jurism_db)

# Initialize result variables
ITEM_FOUND="false"
ITEM_DATA="{}"
CREATED_DURING_TASK="false"

if [ -n "$JURISM_DB" ]; then
    # Python script to extract complex data structure
    python3 -c "
import sqlite3
import json
import os
import sys

db_path = '$JURISM_DB'
task_start = $TASK_START
target_title = 'Adverse Possession'

result = {
    'item_found': False,
    'created_during_task': False,
    'data': {},
    'debug_log': []
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 1. Find item by title
    # fieldID 1 is usually Title
    cursor.execute('''
        SELECT items.itemID, items.dateAdded, items.itemTypeID 
        FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE fieldID = 1 AND value = ?
    ''', (target_title,))
    
    row = cursor.fetchone()
    
    if row:
        item_id, date_added, item_type_id = row
        result['item_found'] = True
        result['data']['itemID'] = item_id
        result['data']['itemTypeID'] = item_type_id
        result['data']['dateAdded'] = date_added
        
        # Check timestamp (simple string comparison works for ISO dates usually, 
        # but better to rely on verifier for strict logic if needed. 
        # Here we just pass the date string.)
        
        # 2. Get all fields
        # Common Zotero/Jurism Field IDs:
        # 1: Title
        # 7: Publication Title (Encyclopedia Title)
        # 3: Series
        # 22: Volume
        # 8: Date
        # 47: Pages
        # 36: Publisher
        
        field_map = {
            1: 'title',
            7: 'publicationTitle',
            3: 'series',
            22: 'volume',
            8: 'date',
            47: 'pages',
            36: 'publisher'
        }
        
        cursor.execute('''
            SELECT fieldID, value 
            FROM itemData 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE itemID = ?
        ''', (item_id,))
        
        fields = {}
        for field_id, value in cursor.fetchall():
            if field_id in field_map:
                fields[field_map[field_id]] = value
            # Also store raw field ID for debugging
            fields[f'fid_{field_id}'] = value
            
        result['data']['fields'] = fields
        
        # 3. Get Creators
        cursor.execute('''
            SELECT firstName, lastName, creatorTypeID 
            FROM itemCreators 
            JOIN creators ON itemCreators.creatorID = creators.creatorID 
            WHERE itemID = ? 
            ORDER BY orderIndex
        ''', (item_id,))
        
        creators = []
        for first, last, type_id in cursor.fetchall():
            creators.append({'firstName': first, 'lastName': last, 'typeID': type_id})
            
        result['data']['creators'] = creators
        
    else:
        result['debug_log'].append('No item found with title: ' + target_title)

    conn.close()
    
except Exception as e:
    result['error'] = str(e)

# Write to temp file
with open('/tmp/py_result.json', 'w') as f:
    json.dump(result, f)
"
    
    # Merge into final JSON
    if [ -f /tmp/py_result.json ]; then
        cat /tmp/py_result.json > /tmp/task_result.json
    else
        echo '{"error": "Python extraction failed"}' > /tmp/task_result.json
    fi
else
    echo '{"error": "Database not found"}' > /tmp/task_result.json
fi

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved:"
cat /tmp/task_result.json
echo "=== Export complete ==="