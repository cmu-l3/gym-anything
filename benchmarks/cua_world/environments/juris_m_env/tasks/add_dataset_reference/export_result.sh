#!/bin/bash
echo "=== Exporting add_dataset_reference result ==="
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find Database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism database not found"
    cat > /tmp/task_result.json << EOF
{
    "error": "Database not found",
    "passed": false
}
EOF
    exit 1
fi

# Query the database for the added item
# We look for an item of type 'dataset' with title 'The Supreme Court Database'
python3 -c "
import sqlite3
import json
import sys
import datetime

db_path = '$JURISM_DB'
task_start = $TASK_START

result = {
    'item_found': False,
    'item_type_correct': False,
    'title': None,
    'date': None,
    'repository': None,
    'url': None,
    'format': None,
    'author_found': False,
    'author_name': '',
    'created_during_task': False,
    'task_start': task_start,
    'screenshot_path': '/tmp/task_final.png'
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Get Item Type ID for 'dataset'
    c.execute(\"SELECT itemTypeID FROM itemTypes WHERE typeName='dataset'\")
    row = c.fetchone()
    if not row:
        # Fallback if 'dataset' type name is different in this schema, though 'dataset' is standard
        dataset_type_id = 37 # Common ID, but risky. Let's check user items.
        print('Warning: Could not find dataset itemTypeID by name')
        dataset_type_id = None
    else:
        dataset_type_id = row['itemTypeID']

    # 2. Find the item
    # We search for title first
    c.execute('''
        SELECT items.itemID, items.itemTypeID, items.dateAdded 
        FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE items.itemTypeID NOT IN (1,3,31) 
        AND itemDataValues.value LIKE '%Supreme Court Database%'
        ORDER BY items.dateAdded DESC LIMIT 1
    ''')
    item = c.fetchone()

    if item:
        result['item_found'] = True
        item_id = item['itemID']
        
        # Check type
        if dataset_type_id and item['itemTypeID'] == dataset_type_id:
            result['item_type_correct'] = True
        
        # Check timestamp
        date_added = item['dateAdded'] # Format: YYYY-MM-DD HH:MM:SS
        try:
            # Convert DB time (UTC usually) to timestamp
            # Python sqlite string to datetime
            dt = datetime.datetime.strptime(date_added, '%Y-%m-%d %H:%M:%S')
            # Assuming DB is local time or UTC. Simple comparison:
            # If created after task start (with small buffer for clock skew)
            # Just rough check: timestamp comparison
            if dt.timestamp() > (task_start - 60):
                result['created_during_task'] = True
        except:
            pass # Keep false if parse fails

        # 3. Get Field Values
        # Helper to get value by field name
        def get_field_value(field_name):
            c.execute('''
                SELECT v.value FROM itemDataValues v
                JOIN itemData d ON v.valueID = d.valueID
                JOIN fields f ON d.fieldID = f.fieldID
                WHERE d.itemID = ? AND f.fieldName = ?
            ''', (item_id, field_name))
            r = c.fetchone()
            return r['value'] if r else None

        result['title'] = get_field_value('title')
        result['date'] = get_field_value('date')
        result['repository'] = get_field_value('repository')
        result['url'] = get_field_value('url')
        result['format'] = get_field_value('medium') # Format in UI usually maps to 'medium' in Zotero schema

        # 4. Check Creators (Author)
        c.execute('''
            SELECT c.firstName, c.lastName, ct.creatorType 
            FROM creators c
            JOIN itemCreators ic ON c.creatorID = ic.creatorID
            JOIN creatorTypes ct ON ic.creatorTypeID = ct.creatorTypeID
            WHERE ic.itemID = ?
        ''', (item_id,))
        creators = c.fetchall()
        for cr in creators:
            name = f\"{cr['firstName']} {cr['lastName']}\"
            if 'Spaeth' in cr['lastName']:
                result['author_found'] = True
                result['author_name'] = name

    conn.close()

except Exception as e:
    result['error'] = str(e)
    print(f'Error querying DB: {e}')

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="