#!/bin/bash
echo "=== Exporting organize_classics_by_tag results ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Python script to inspect DB and generate JSON result
# We use Python because complex SQL joins + logic is cleaner than bash/sqlite3 one-liners
python3 -c "
import sqlite3
import json
import os
import sys

db_path = '$DB'
cutoff_year = 1970
target_coll_name = 'History of Computing'
target_tag_name = 'classic-era'

result = {
    'collection_exists': False,
    'collection_id': None,
    'tag_exists': False,
    'tag_id': None,
    'classic_items_in_coll': 0,
    'modern_items_in_coll': 0,
    'classic_items_tagged': 0,
    'modern_items_tagged': 0,
    'total_classic_items': 0,
    'total_modern_items': 0,
    'details': []
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 1. Get Collection ID
    cursor.execute('SELECT collectionID FROM collections WHERE collectionName = ?', (target_coll_name,))
    row = cursor.fetchone()
    if row:
        result['collection_exists'] = True
        result['collection_id'] = row[0]

    # 2. Get Tag ID
    cursor.execute('SELECT tagID FROM tags WHERE name = ?', (target_tag_name,))
    row = cursor.fetchone()
    if row:
        result['tag_exists'] = True
        result['tag_id'] = row[0]

    # 3. Analyze all items
    # We need to map itemID -> Year
    # Field 6 is Date. Values are in itemDataValues.
    # We join items -> itemData -> itemDataValues
    query = '''
        SELECT i.itemID, v.value
        FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE i.itemTypeID != 14 AND i.itemTypeID != 1  -- Exclude attachments/notes
        AND d.fieldID = 6 -- Date field
    '''
    cursor.execute(query)
    all_items = cursor.fetchall()

    for item_id, date_str in all_items:
        # Extract year (simple 4 digit extraction)
        # Dates can be '1905', '1905-06', 'June 1905', etc.
        # Simple heuristic: find first 4 consecutive digits
        import re
        year_match = re.search(r'\d{4}', str(date_str))
        if not year_match:
            continue
        
        year = int(year_match.group(0))
        is_classic = year < cutoff_year

        if is_classic:
            result['total_classic_items'] += 1
        else:
            result['total_modern_items'] += 1

        # Check if in collection
        in_coll = False
        if result['collection_id']:
            cursor.execute('SELECT 1 FROM collectionItems WHERE collectionID=? AND itemID=?', 
                           (result['collection_id'], item_id))
            if cursor.fetchone():
                in_coll = True
                if is_classic:
                    result['classic_items_in_coll'] += 1
                else:
                    result['modern_items_in_coll'] += 1

        # Check if tagged
        is_tagged = False
        if result['tag_id']:
            cursor.execute('SELECT 1 FROM itemTags WHERE tagID=? AND itemID=?', 
                           (result['tag_id'], item_id))
            if cursor.fetchone():
                is_tagged = True
                if is_classic:
                    result['classic_items_tagged'] += 1
                else:
                    result['modern_items_tagged'] += 1
        
        result['details'].append({
            'item_id': item_id,
            'year': year,
            'is_classic': is_classic,
            'in_collection': in_coll,
            'is_tagged': is_tagged
        })

    conn.close()

except Exception as e:
    result['error'] = str(e)

# Output JSON to stdout
print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Check if JSON generation worked
if [ ! -s /tmp/task_result.json ]; then
    echo "{\"error\": \"Failed to generate result JSON\"}" > /tmp/task_result.json
fi

# Ensure permissions
chmod 666 /tmp/task_result.json
cat /tmp/task_result.json

echo "=== Export complete ==="