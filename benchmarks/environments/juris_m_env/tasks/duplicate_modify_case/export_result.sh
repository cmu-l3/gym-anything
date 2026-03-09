#!/bin/bash
echo "=== Exporting duplicate_modify_case Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism DB not found"
    echo '{"error": "DB not found"}' > /tmp/duplicate_modify_case_result.json
    exit 1
fi

# We need to export all "Brown v. Board" items to verify:
# 1. The original still exists and is unchanged
# 2. A new one exists with correct changes

# Python script to query DB and export rich JSON
python3 -c "
import sqlite3
import json
import os

db_path = '$JURISM_DB'
task_start = $TASK_START
output_path = '/tmp/duplicate_modify_case_result.json'

result = {
    'task_start': task_start,
    'items': []
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Find all case items (itemTypeID=9) where caseName (fieldID=58) contains 'Brown v. Board'
    c.execute('''
        SELECT DISTINCT items.itemID, items.dateAdded, items.dateModified
        FROM items
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        WHERE items.itemTypeID = 9
          AND itemData.fieldID = 58
          AND itemDataValues.value LIKE '%Brown v. Board%'
    ''')
    rows = c.fetchall()

    for row in rows:
        item_id = row['itemID']
        # Convert DB dates (iso string) to timestamp roughly if possible,
        # but for verification we primarily look at the string comparison or dateAdded ordering.
        # Jurism stores dates as 'YYYY-MM-DD HH:MM:SS'.

        item_data = {
            'itemID': item_id,
            'dateAdded': row['dateAdded'],
            'caseName': None,
            'reporterVolume': None,
            'firstPage': None,
            'dateDecided': None,
            'abstractNote': None
        }

        # Fetch field values
        # Field IDs: 58=caseName, 66=reporterVolume, 67=firstPage, 69=dateDecided, 2=abstractNote
        field_map = {
            58: 'caseName',
            66: 'reporterVolume',
            67: 'firstPage',
            69: 'dateDecided',
            2: 'abstractNote'
        }

        c2 = conn.cursor()
        c2.execute('''
            SELECT fieldID, value
            FROM itemData
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            WHERE itemID = ?
        ''', (item_id,))
        
        for field_row in c2.fetchall():
            fid = field_row[0]
            val = field_row[1]
            if fid in field_map:
                item_data[field_map[fid]] = val

        result['items'].append(item_data)

    conn.close()

except Exception as e:
    result['error'] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f'Exported {len(result[\"items\"])} items to {output_path}')
"

# Handle permissions
chmod 666 /tmp/duplicate_modify_case_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/duplicate_modify_case_result.json