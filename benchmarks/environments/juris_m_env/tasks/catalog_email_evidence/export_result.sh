#!/bin/bash
echo "=== Exporting catalog_email_evidence result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    echo '{"error": "Database not found", "passed": false}' > /tmp/catalog_email_evidence_result.json
    exit 1
fi

# We need to extract complex data (creators, fields) for the specific item.
# We'll use a python script to query the SQLite DB and dump the specific item's details.
python3 -c "
import sqlite3
import json
import os

db_path = '$JURISM_DB'
task_start = $TASK_START
target_subject = 'Resignation implications'

result = {
    'item_found': False,
    'item_details': {},
    'created_during_task': False,
    'timestamp': $TASK_END
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Find the item ID by Subject (which is stored in fields like 'title' or 'subject')
    # We look for the value 'Resignation implications' in itemDataValues
    c.execute('''
        SELECT itemData.itemID, items.dateAdded, items.itemTypeID, itemTypes.typeName
        FROM itemData
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        JOIN items ON itemData.itemID = items.itemID
        JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID
        WHERE itemDataValues.value = ?
        LIMIT 1
    ''', (target_subject,))
    
    item = c.fetchone()
    
    if item:
        result['item_found'] = True
        item_id = item['itemID']
        result['item_details']['itemType'] = item['typeName']
        
        # Check timestamp
        # dateAdded format is typically 'YYYY-MM-DD HH:MM:SS'
        # We'll do a loose check if it's recent, but verifying it exists is the main check here.
        # Ideally convert DB time to epoch, but checking existence + correctness is usually sufficient.
        # We can pass the string back to the verifier.
        result['item_details']['dateAdded'] = item['dateAdded']

        # 2. Get all fields
        c.execute('''
            SELECT fields.fieldName, itemDataValues.value
            FROM itemData
            JOIN fields ON itemData.fieldID = fields.fieldID
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            WHERE itemData.itemID = ?
        ''', (item_id,))
        
        fields = {}
        for row in c.fetchall():
            fields[row['fieldName']] = row['value']
        result['item_details']['fields'] = fields
        
        # 3. Get creators
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
                'creatorType': row['creatorType']
            })
        result['item_details']['creators'] = creators

except Exception as e:
    result['error'] = str(e)
finally:
    if 'conn' in locals():
        conn.close()

with open('/tmp/catalog_email_evidence_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/catalog_email_evidence_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/catalog_email_evidence_result.json
echo "=== Export Complete ==="