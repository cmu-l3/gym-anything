#!/bin/bash
# Export script for add_dictionary_entry task
echo "=== Exporting add_dictionary_entry Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/dictionary_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/add_dictionary_entry_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# We need to find the item the user created.
# We look for an item with title "Stare Decisis" created after task start.
# If multiple exist, we take the most recent one.

# Python script to extract complex relational data from SQLite
python3 -c "
import sqlite3
import json
import sys

db_path = '$JURISM_DB'
task_start = $TASK_START

result = {
    'item_found': False,
    'item_type': None,
    'title': None,
    'dictionary_title': None,
    'date': None,
    'edition': None,
    'publisher': None,
    'creators': [],
    'created_during_task': False,
    'timestamp_check': {'task_start': task_start, 'item_date_added': None}
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Find the item ID for 'Stare Decisis'
    # Field 1 is usually 'title'
    c.execute('''
        SELECT items.itemID, items.dateAdded, itemTypes.typeName
        FROM items
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID
        WHERE itemData.fieldID = 1 
        AND LOWER(itemDataValues.value) = 'stare decisis'
        AND items.itemTypeID NOT IN (1,3,31)
        ORDER BY items.dateAdded DESC LIMIT 1
    ''')
    
    row = c.fetchone()
    
    if row:
        result['item_found'] = True
        item_id = row['itemID']
        result['item_type'] = row['typeName']
        result['timestamp_check']['item_date_added'] = row['dateAdded']
        
        # Check anti-gaming timestamp
        # dateAdded format is usually 'YYYY-MM-DD HH:MM:SS'
        # We'll just pass the string to python verifier to parse
        
        # 2. Get Metadata Fields
        # We need to map fieldIDs. Standard Zotero/Jurism Schema:
        # 1: title
        # 7: publicationTitle (Dictionary Title)
        # 8: date
        # 22: volume
        # 16: publisher (check schema varies, usually 16 or 45)
        # 25: edition
        
        c.execute('''
            SELECT fields.fieldName, itemDataValues.value
            FROM itemData
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            JOIN fields ON itemData.fieldID = fields.fieldID
            WHERE itemData.itemID = ?
        ''', (item_id,))
        
        fields = {r['fieldName']: r['value'] for r in c.fetchall()}
        result['title'] = fields.get('title')
        result['dictionary_title'] = fields.get('publicationTitle')
        result['date'] = fields.get('date')
        result['edition'] = fields.get('edition')
        result['publisher'] = fields.get('publisher')
        
        # 3. Get Creators
        c.execute('''
            SELECT creators.firstName, creators.lastName, creatorTypes.creatorType
            FROM itemCreators
            JOIN creators ON itemCreators.creatorID = creators.creatorID
            JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
            WHERE itemCreators.itemID = ?
            ORDER BY itemCreators.orderIndex
        ''', (item_id,))
        
        creators = []
        for cr in c.fetchall():
            creators.append({
                'firstName': cr['firstName'],
                'lastName': cr['lastName'],
                'type': cr['creatorType']
            })
        result['creators'] = creators

    conn.close()

except Exception as e:
    result['error'] = str(e)

with open('/tmp/add_dictionary_entry_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

chmod 666 /tmp/add_dictionary_entry_result.json 2>/dev/null || true
echo "Result saved to /tmp/add_dictionary_entry_result.json"
cat /tmp/add_dictionary_entry_result.json
echo "=== Export Complete ==="