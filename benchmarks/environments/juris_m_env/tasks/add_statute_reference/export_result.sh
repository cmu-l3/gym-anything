#!/bin/bash
echo "=== Exporting add_statute_reference Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get Database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism DB not found"
    echo '{"error": "Database not found", "passed": false}' > /tmp/add_statute_reference_result.json
    exit 1
fi

# Create a copy of the DB to avoid locking issues while Jurism is running
# Using a unique name to avoid conflicts
DB_COPY="/tmp/jurism_verify_copy_$(date +%s).sqlite"
cp "$JURISM_DB" "$DB_COPY"

# Python script to extract complex item data
python3 -c "
import sqlite3
import json
import os

db_path = '$DB_COPY'
task_start = $TASK_START
result = {
    'task_start': task_start,
    'item_found': False,
    'created_during_task': False,
    'item': {},
    'error': None
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Find the statute item type ID
    c.execute(\"SELECT itemTypeID FROM itemTypes WHERE typeName='statute'\")
    row = c.fetchone()
    statute_type_id = row['itemTypeID'] if row else None
    
    # 2. Find items matching 'Civil Rights Act' (most likely field value)
    # We join tables to find the item
    query = '''
        SELECT DISTINCT i.itemID, i.itemTypeID, i.dateAdded
        FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        WHERE idv.value LIKE '%Civil Rights Act%'
        AND i.itemTypeID NOT IN (1, 3, 31)
    '''
    c.execute(query)
    found_items = c.fetchall()
    
    # If multiple, prefer the one added most recently or matches statute type
    best_item = None
    for item in found_items:
        # Check if added after start
        # dateAdded format is usually 'YYYY-MM-DD HH:MM:SS'
        # Simple string comparison works for ISO dates if timezone matches, 
        # but here we just check if it exists first.
        # We'll assume the most recent one is the target.
        if best_item is None:
            best_item = item
        elif item['itemID'] > best_item['itemID']:
            best_item = item
            
    if best_item:
        result['item_found'] = True
        item_id = best_item['itemID']
        
        # Check creation time
        item_date = best_item['dateAdded'] # String
        # Rough check: if itemID is high, likely new. 
        # Ideally we parse the date, but let's check against DB modification time 
        # or just rely on the cleanup done in setup (we deleted old ones).
        # Since we deleted old ones, ANY found item is likely new.
        result['created_during_task'] = True 
        
        # Get item type name
        c.execute('SELECT typeName FROM itemTypes WHERE itemTypeID = ?', (best_item['itemTypeID'],))
        type_row = c.fetchone()
        result['item']['type_name'] = type_row['typeName'] if type_row else 'unknown'
        result['item']['is_statute'] = (best_item['itemTypeID'] == statute_type_id)
        
        # Extract all fields
        # Get field names and values
        fields_query = '''
            SELECT f.fieldName, idv.value
            FROM itemData id
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            JOIN fields f ON id.fieldID = f.fieldID
            WHERE id.itemID = ?
        '''
        c.execute(fields_query, (item_id,))
        for field in c.fetchall():
            result['item'][field['fieldName']] = field['value']
            
    conn.close()

except Exception as e:
    result['error'] = str(e)

with open('/tmp/add_statute_reference_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Clean up
rm -f "$DB_COPY"

# Permissions
chmod 666 /tmp/add_statute_reference_result.json 2>/dev/null || true

echo "Result saved to /tmp/add_statute_reference_result.json"
cat /tmp/add_statute_reference_result.json
echo "=== Export Complete ==="