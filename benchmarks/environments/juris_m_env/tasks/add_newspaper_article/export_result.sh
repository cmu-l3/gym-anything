#!/bin/bash
echo "=== Exporting add_newspaper_article result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_item_count.txt 2>/dev/null || echo "0")

# Get DB path
JURISM_DB=$(get_jurism_db)

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism database not found"
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# Use Python to extract the specific item and its metadata
# This is more robust than bash/sqlite3 one-liners for the Zotero schema
python3 -c "
import sqlite3
import json
import sys
import os
from datetime import datetime

db_path = '$JURISM_DB'
task_start = $TASK_START
target_title_fragment = 'Same-Sex Marriage'

result = {
    'task_start': task_start,
    'task_end': $TASK_END,
    'initial_count': $INITIAL_COUNT,
    'current_count': 0,
    'item_found': False,
    'item_data': {},
    'created_during_task': False
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    # Get current count
    cursor.execute('SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)')
    result['current_count'] = cursor.fetchone()[0]
    
    # Find the specific item ID
    # We look for a newspaperArticle (typeName='newspaperArticle')
    # and title containing the target fragment
    cursor.execute('''
        SELECT i.itemID, i.dateAdded, it.typeName 
        FROM items i
        JOIN itemTypes it ON i.itemTypeID = it.itemTypeID
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        JOIN fields f ON id.fieldID = f.fieldID
        WHERE it.typeName = 'newspaperArticle'
        AND f.fieldName = 'title'
        AND idv.value LIKE ?
        ORDER BY i.dateAdded DESC LIMIT 1
    ''', ('%' + target_title_fragment + '%',))
    
    item = cursor.fetchone()
    
    if item:
        result['item_found'] = True
        item_id = item['itemID']
        date_added = item['dateAdded']
        
        # Check creation time
        try:
            # Format usually: '2023-01-01 12:00:00'
            dt = datetime.strptime(date_added, '%Y-%m-%d %H:%M:%S')
            if dt.timestamp() > task_start:
                result['created_during_task'] = True
        except:
            pass
            
        # Extract all fields for this item
        item_data = {'type': item['typeName']}
        
        # Get metadata fields
        cursor.execute('''
            SELECT f.fieldName, idv.value
            FROM itemData id
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            JOIN fields f ON id.fieldID = f.fieldID
            WHERE id.itemID = ?
        ''', (item_id,))
        
        for row in cursor.fetchall():
            item_data[row['fieldName']] = row['value']
            
        # Get creators (authors)
        cursor.execute('''
            SELECT c.firstName, c.lastName, ct.creatorType
            FROM itemCreators ic
            JOIN creators c ON ic.creatorID = c.creatorID
            JOIN creatorTypes ct ON ic.creatorTypeID = ct.creatorTypeID
            WHERE ic.itemID = ?
            ORDER BY ic.orderIndex
        ''', (item_id,))
        
        creators = []
        for row in cursor.fetchall():
            creators.append({
                'firstName': row['firstName'],
                'lastName': row['lastName'],
                'type': row['creatorType']
            })
        item_data['creators'] = creators
        
        result['item_data'] = item_data

    conn.close()
    
except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json