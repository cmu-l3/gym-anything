#!/bin/bash
# Export result for annotate_extra_field task
# Queries SQLite DB for the content of the 'extra' field for all items

echo "=== Exporting annotate_extra_field result ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to handle complex SQL parsing and JSON generation reliably
python3 -c "
import sqlite3
import json
import os
import sys

db_path = '$DB_PATH'
task_start = int($TASK_START)

result = {
    'task_start': task_start,
    'papers': {},
    'others_polluted': 0,
    'db_error': False
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 1. Get fieldID for 'extra'
    cursor.execute(\"SELECT fieldID FROM fields WHERE fieldName = 'extra'\")
    row = cursor.fetchone()
    if not row:
        # Should not happen in valid Zotero DB
        raise Exception('Extra field ID not found')
    extra_field_id = row[0]

    # 2. Get title field ID (usually 1, but safe to query)
    cursor.execute(\"SELECT fieldID FROM fields WHERE fieldName = 'title'\")
    title_field_id = cursor.fetchone()[0]

    # 3. Get all items with their titles and modification dates
    # items table: itemID, dateModified
    # itemData/Values for title
    query_items = f\"\"\"
        SELECT i.itemID, i.dateModified, v.value 
        FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE d.fieldID = {title_field_id}
          AND i.itemTypeID NOT IN (1, 14) -- Exclude notes and attachments
    \"\"\"
    cursor.execute(query_items)
    items = cursor.fetchall()

    for item_id, date_mod, title in items:
        # Get Extra field content for this item
        query_extra = f\"\"\"
            SELECT v.value 
            FROM itemData d
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.itemID = {item_id} AND d.fieldID = {extra_field_id}
        \"\"\"
        cursor.execute(query_extra)
        extra_row = cursor.fetchone()
        extra_content = extra_row[0] if extra_row else \"\"

        # Store data
        # Check if this is one of our target papers (substring match handled in verifier usually, 
        # but we dump everything to JSON so verifier can process)
        result['papers'][str(item_id)] = {
            'title': title,
            'extra_content': extra_content,
            'date_modified': date_mod
        }

    conn.close()

except Exception as e:
    result['db_error'] = str(e)

# Write to temp file first
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Move to final location safely
mv /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="