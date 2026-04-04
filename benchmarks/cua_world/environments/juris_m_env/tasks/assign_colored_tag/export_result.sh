#!/bin/bash
echo "=== Exporting assign_colored_tag result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "{\"error\": \"Database not found\"}" > /tmp/task_result.json
    exit 0
fi

# To ensure WAL is flushed and we get latest data, we ideally stop Jurism or wait.
# However, stopping app might be disruptive if we want to check running state.
# SQLite in WAL mode usually allows reading. We will try reading directly.

# We will export raw data to JSON using Python for the verifier to process.
# This avoids complex bash JSON construction.

python3 -c "
import sqlite3
import json
import os

db_path = '$JURISM_DB'
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'tag_found': False,
    'tag_color_assigned': False,
    'tagged_items': [],
    'total_tagged_count': 0,
    'settings_dump': []
}

try:
    # Open DB in read-only mode using URI
    conn = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True)
    cursor = conn.cursor()
    
    # 1. Check Tag Existence
    cursor.execute(\"SELECT tagID, name FROM tags WHERE name = 'Landmark Decision'\")
    tag_row = cursor.fetchone()
    
    if tag_row:
        tag_id = tag_row[0]
        result['tag_found'] = True
        
        # 2. Check Items with this tag
        # Join items -> itemData (for title/caseName)
        # itemData fields: 1=title, 58=caseName
        query = \"\"\"
            SELECT items.itemID, idv.value 
            FROM itemTags it
            JOIN items ON it.itemID = items.itemID
            JOIN itemData id ON items.itemID = id.itemID
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            WHERE it.tagID = ? AND id.fieldID IN (1, 58)
        \"\"\"
        cursor.execute(query, (tag_id,))
        rows = cursor.fetchall()
        
        # Deduplicate by itemID (in case multiple title fields somehow match, rare)
        seen_ids = set()
        for iid, name in rows:
            if iid not in seen_ids:
                result['tagged_items'].append(name)
                seen_ids.add(iid)
                
        result['total_tagged_count'] = len(result['tagged_items'])
        
    # 3. Check Color Settings
    # Colors are stored in 'settings' or 'syncedSettings' table under keys like 'tagColors'
    # The value is usually a JSON string: {\"Landmark Decision\":\"#FF0000\", ...}
    cursor.execute(\"SELECT setting, value FROM settings WHERE setting LIKE '%tagColor%'\")
    settings_rows = cursor.fetchall()
    
    cursor.execute(\"SELECT setting, value FROM syncedSettings WHERE setting LIKE '%tagColor%'\")
    settings_rows.extend(cursor.fetchall())
    
    for setting, value in settings_rows:
        result['settings_dump'].append({'setting': setting, 'value': value})
        if 'Landmark Decision' in str(value):
            result['tag_color_assigned'] = True

    conn.close()

except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="