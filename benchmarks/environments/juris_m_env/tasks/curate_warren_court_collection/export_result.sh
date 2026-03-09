#!/bin/bash
echo "=== Exporting Curate Warren Court Collection Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get DB path
DB_PATH=$(get_jurism_db)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

if [ -z "$DB_PATH" ]; then
    echo "ERROR: Database not found"
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# Use Python to inspect the database and generate a JSON report
# This is much more reliable than complex bash/sqlite3 piping for the EAV structure
python3 -c "
import sqlite3
import json
import os
import sys

db_path = '$DB_PATH'
task_start = $TASK_START
output_path = '/tmp/task_result.json'

result = {
    'collection_exists': False,
    'collection_id': None,
    'item_count': 0,
    'items': [],
    'task_start': task_start,
    'timestamp': '$TASK_END'
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # 1. Find the 'Warren Court' collection
    cursor.execute('SELECT collectionID, dateAdded FROM collections WHERE collectionName = ?', ('Warren Court',))
    coll_row = cursor.fetchone()

    if coll_row:
        result['collection_exists'] = True
        result['collection_id'] = coll_row['collectionID']
        
        # Check creation time (anti-gaming)
        # Jurism stores dates as strings 'YYYY-MM-DD HH:MM:SS', we can check loosely or just rely on items
        
        # 2. Get items in this collection
        # Join items -> itemData -> itemDataValues to get Case Name (field 58) and Date Decided (field 69)
        # Note: For cases, caseName is 58. For articles, title is 1.
        
        query = '''
        SELECT 
            i.itemID, 
            i.itemTypeID,
            (SELECT value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=58) as caseName,
            (SELECT value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=1) as title,
            (SELECT value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=69) as dateDecided,
            (SELECT value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=8) as datePub
        FROM collectionItems ci
        JOIN items i ON ci.itemID = i.itemID
        WHERE ci.collectionID = ?
        '''
        
        cursor.execute(query, (coll_row['collectionID'],))
        items = cursor.fetchall()
        
        result['item_count'] = len(items)
        
        for item in items:
            # Determine name and date based on type
            name = item['caseName'] if item['caseName'] else item['title']
            date = item['dateDecided'] if item['dateDecided'] else item['datePub']
            
            result['items'].append({
                'itemID': item['itemID'],
                'itemTypeID': item['itemTypeID'], # 9 is Case
                'name': name,
                'date': date
            })

    conn.close()

except Exception as e:
    result['error'] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f'Exported result to {output_path}')
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json

echo "=== Export Complete ==="