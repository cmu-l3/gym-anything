#!/bin/bash
echo "=== Exporting add_podcast_reference Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get DB path
JURISM_DB=$(get_jurism_db)

# Use Python to inspect the complicated Zotero/Jurism schema and export result
python3 -c "
import sqlite3
import json
import os
import datetime

db_path = '$JURISM_DB'
task_start = $TASK_START
output_file = '/tmp/add_podcast_result.json'

result = {
    'task_start': task_start,
    'task_end': $TASK_END,
    'item_found': False,
    'created_during_task': False,
    'metadata': {},
    'creators': []
}

if not os.path.exists(db_path):
    result['error'] = 'Database not found'
else:
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        
        # 1. Find the item by Title 'The Alibi'
        # We look for value 'The Alibi' in itemDataValues linked to an item
        c.execute('''
            SELECT items.itemID, items.dateAdded, itemTypes.typeName
            FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID
            WHERE itemDataValues.value = 'The Alibi'
            LIMIT 1
        ''')
        
        row = c.fetchone()
        if row:
            item_id, date_added, type_name = row
            result['item_found'] = True
            result['item_id'] = item_id
            result['item_type'] = type_name
            result['date_added'] = date_added
            
            # Check if created during task
            # SQLite date format is usually YYYY-MM-DD HH:MM:SS
            try:
                # Parse SQLite date string to timestamp
                # Usually in UTC or local depending on Jurism version, but comparison is safer if we handle format
                # Simple string comparison works if format is ISO and we trust system clock
                # Let's try to convert task_start to string for comparison or vice versa
                pass
            except:
                pass
                
            # 2. Get all metadata values for this item
            # We fetch all values associated with this item to check for presence of required strings
            # This avoids needing to map exact fieldIDs which can vary
            c.execute('''
                SELECT itemDataValues.value 
                FROM itemData 
                JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
                WHERE itemData.itemID = ?
            ''', (item_id,))
            
            all_values = [r[0] for r in c.fetchall()]
            result['all_values'] = all_values
            
            # 3. Get Creators (Performer)
            c.execute('''
                SELECT creators.firstName, creators.lastName, creatorTypes.creatorType
                FROM itemCreators
                JOIN creators ON itemCreators.creatorID = creators.creatorID
                JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
                WHERE itemCreators.itemID = ?
                ORDER BY itemCreators.orderIndex
            ''', (item_id,))
            
            creators = []
            for c_row in c.fetchall():
                creators.append({
                    'firstName': c_row[0],
                    'lastName': c_row[1],
                    'type': c_row[2]
                })
            result['creators'] = creators
            
            # Determine if created during task
            # date_added is string like '2023-10-25 10:00:00'
            # task_start is unix timestamp
            try:
                dt_added = datetime.datetime.strptime(date_added, '%Y-%m-%d %H:%M:%S')
                ts_added = dt_added.timestamp()
                # Allow small buffer (clock skew)
                if ts_added >= (task_start - 60):
                    result['created_during_task'] = True
            except Exception as e:
                # Fallback: Just assume yes if item exists and we cleaned up before
                # print(f'Date parse error: {e}')
                # Since we cleaned up 'The Alibi' items in setup, any finding is likely new
                result['created_during_task'] = True

        conn.close()
    except Exception as e:
        result['error'] = str(e)

# Save result
with open(output_file, 'w') as f:
    json.dump(result, f, indent=4)
"

# Handle permissions
chmod 666 /tmp/add_podcast_result.json 2>/dev/null || true
echo "Result exported to /tmp/add_podcast_result.json"
cat /tmp/add_podcast_result.json
echo "=== Export Complete ==="