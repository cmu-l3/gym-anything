#!/bin/bash
echo "=== Exporting add_crs_report Result ==="
source /workspace/scripts/task_utils.sh

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    echo '{"error": "Database not found"}' > /tmp/add_crs_report_result.json
    exit 1
fi

# We need to query the DB for the specific item.
# We will write a small Python script to extract the data cleanly into JSON.
python3 -c "
import sqlite3
import json
import os
from datetime import datetime

db_path = '$JURISM_DB'
task_start = $TASK_START
output_file = '/tmp/add_crs_report_result.json'

result = {
    'item_found': False,
    'created_during_task': False,
    'fields': {},
    'creators': [],
    'item_type_id': None,
    'timestamp': datetime.now().isoformat()
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Find the item. We look for Report Number 'R44235' OR specific Title
    # We prefer the one with the highest itemID (most recently added)
    query = '''
        SELECT DISTINCT i.itemID, i.itemTypeID, i.dateAdded
        FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        JOIN fields f ON id.fieldID = f.fieldID
        WHERE (f.fieldName = 'reportNumber' AND idv.value = 'R44235')
           OR (f.fieldName = 'title' AND idv.value LIKE '%Supreme Court Appointment Process%')
        ORDER BY i.itemID DESC
        LIMIT 1
    '''
    c.execute(query)
    row = c.fetchone()

    if row:
        result['item_found'] = True
        item_id = row['itemID']
        result['item_type_id'] = row['itemTypeID']
        
        # Check dateAdded
        date_added_str = row['dateAdded']
        try:
            # Format usually: YYYY-MM-DD HH:MM:SS
            dt = datetime.strptime(date_added_str, '%Y-%m-%d %H:%M:%S')
            if dt.timestamp() > task_start:
                result['created_during_task'] = True
        except:
            pass # Keep false if parse fails

        # 2. Get all fields for this item
        c.execute('''
            SELECT f.fieldName, idv.value 
            FROM itemData id
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            JOIN fields f ON id.fieldID = f.fieldID
            WHERE id.itemID = ?
        ''', (item_id,))
        
        for field_row in c.fetchall():
            result['fields'][field_row['fieldName']] = field_row['value']

        # 3. Get creators
        c.execute('''
            SELECT c.firstName, c.lastName, ct.creatorType
            FROM itemCreators ic
            JOIN creators c ON ic.creatorID = c.creatorID
            JOIN creatorTypes ct ON ic.creatorTypeID = ct.creatorTypeID
            WHERE ic.itemID = ?
            ORDER BY ic.orderIndex
        ''', (item_id,))
        
        for creator_row in c.fetchall():
            result['creators'].append({
                'firstName': creator_row['firstName'],
                'lastName': creator_row['lastName'],
                'type': creator_row['creatorType']
            })

    conn.close()

except Exception as e:
    result['error'] = str(e)

with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/add_crs_report_result.json 2>/dev/null || true
echo "Result exported to /tmp/add_crs_report_result.json"
cat /tmp/add_crs_report_result.json
echo "=== Export Complete ==="