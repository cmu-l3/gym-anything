#!/bin/bash
echo "=== Exporting add_letter_reference Result ==="
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TASK_START_DT=$(date -d "@$TASK_START" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "1970-01-01 00:00:00")

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism DB not found"
    echo '{"error": "DB not found"}' > /tmp/add_letter_reference_result.json
    exit 1
fi

# 3. Query DB for the target item
# We look for an item with title roughly matching "Letter from Birmingham Jail"
# We extract: itemID, typeName, title, date, abstract, letterType, creators
# Note: In Zotero schema, 'letter' is a specific itemType.

# Python script to handle complex extraction and JSON formatting safely
python3 << EOF > /tmp/add_letter_reference_result.json
import sqlite3
import json
import sys

db_path = "$JURISM_DB"
task_start_dt = "$TASK_START_DT"

result = {
    "found": False,
    "item": {},
    "creators": [],
    "created_during_task": False,
    "screenshot_path": "/tmp/task_final.png"
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Find item ID by title
    # Field 1 is usually Title
    c.execute('''
        SELECT items.itemID, items.dateAdded, itemTypes.typeName
        FROM items
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID
        JOIN fields ON itemData.fieldID = fields.fieldID
        WHERE fields.fieldName = 'title'
          AND itemDataValues.value LIKE '%Letter from Birmingham Jail%'
        ORDER BY items.dateAdded DESC
        LIMIT 1
    ''')
    row = c.fetchone()

    if row:
        item_id, date_added, type_name = row
        result['found'] = True
        result['created_during_task'] = (date_added > task_start_dt)
        result['item']['id'] = item_id
        result['item']['type'] = type_name
        result['item']['date_added'] = date_added

        # Get all field data for this item
        c.execute('''
            SELECT fields.fieldName, itemDataValues.value
            FROM itemData
            JOIN fields ON itemData.fieldID = fields.fieldID
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            WHERE itemData.itemID = ?
        ''', (item_id,))
        fields = {r[0]: r[1] for r in c.fetchall()}
        result['item']['fields'] = fields

        # Get creators
        c.execute('''
            SELECT creators.firstName, creators.lastName, creatorTypes.creatorType
            FROM itemCreators
            JOIN creators ON itemCreators.creatorID = creators.creatorID
            JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
            WHERE itemCreators.itemID = ?
            ORDER BY itemCreators.orderIndex
        ''', (item_id,))
        creators = [{'first': r[0], 'last': r[1], 'role': r[2]} for r in c.fetchall()]
        result['creators'] = creators

    conn.close()

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result, indent=2))
EOF

chmod 666 /tmp/add_letter_reference_result.json 2>/dev/null || true
echo "Result exported to /tmp/add_letter_reference_result.json"
cat /tmp/add_letter_reference_result.json
echo "=== Export Complete ==="