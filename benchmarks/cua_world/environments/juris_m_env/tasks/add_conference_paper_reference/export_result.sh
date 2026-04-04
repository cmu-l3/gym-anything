#!/bin/bash
echo "=== Exporting add_conference_paper_reference Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    echo '{"error": "Jurism database not found"}' > /tmp/task_result.json
    exit 1
fi

# Query DB for the item
# We look for an item with title containing "Explainable Legal Prediction"
# Fields:
# 1 = Title
# 12 = Publication Title (Proceedings Title)
# 21 = Conference Name
# 27 = Publisher
# 8 = Date
# 47 = Pages

# Extract item details using Python for reliable JSON formatting
python3 << EOF
import sqlite3
import json
import os
import sys

db_path = "$JURISM_DB"
task_start = int("$TASK_START")

result = {
    "found": False,
    "created_during_task": False,
    "item": {}
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Find item ID by title
    c.execute('''
        SELECT items.itemID, items.itemTypeID, items.dateAdded
        FROM items
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        WHERE itemData.fieldID = 1 AND LOWER(itemDataValues.value) LIKE '%explainable%legal%prediction%'
        ORDER BY items.dateAdded DESC LIMIT 1
    ''')
    row = c.fetchone()

    if row:
        item_id, item_type_id, date_added = row
        result["found"] = True
        result["item"]["item_id"] = item_id
        result["item"]["item_type_id"] = item_type_id
        result["item"]["date_added"] = date_added

        # Check if created after task start
        # dateAdded format is usually "YYYY-MM-DD HH:MM:SS"
        # Simple string comparison works if format is standard ISO-like,
        # but robust check uses timestamp conversion or just assumes new if ID is high
        # Here we'll pass the string to python verifier or just trust checks there.
        # We can also check if date_added > timestamp logic here if we convert.

        # Fetch field values
        fields = {
            1: "title",
            12: "proceedings_title",
            21: "conference_name",
            27: "publisher",
            8: "date",
            47: "pages"
        }

        for fid, fname in fields.items():
            c.execute('''
                SELECT value FROM itemData
                JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
                WHERE itemData.itemID = ? AND itemData.fieldID = ?
            ''', (item_id, fid))
            val_row = c.fetchone()
            if val_row:
                result["item"][fname] = val_row[0]

        # Fetch creators
        c.execute('''
            SELECT creators.firstName, creators.lastName, itemCreators.orderIndex
            FROM creators
            JOIN itemCreators ON creators.creatorID = itemCreators.creatorID
            WHERE itemCreators.itemID = ?
            ORDER BY itemCreators.orderIndex ASC
        ''', (item_id,))
        creators = []
        for c_row in c.fetchall():
            creators.append({"first": c_row[0], "last": c_row[1]})
        result["item"]["creators"] = creators

    conn.close()

except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="