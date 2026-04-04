#!/bin/bash
echo "=== Exporting consolidate_case_notes Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    echo '{"error": "DB not found"}' > /tmp/task_result.json
    exit 1
fi

# We need to find the Gideon case and its notes
# We export this data to JSON using Python
python3 -c "
import sqlite3
import json
import os

db_path = '$JURISM_DB'
task_start = $TASK_START
result = {
    'task_start': task_start,
    'gideon_found': False,
    'note_count': 0,
    'notes': [],
    'screenshot_path': '/tmp/task_final.png'
}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        
        # Find Gideon ID
        c.execute(\"SELECT items.itemID FROM items JOIN itemData ON items.itemID=itemData.itemID JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE fieldID=58 AND value LIKE '%Gideon v. Wainwright%'\")
        row = c.fetchone()
        
        if row:
            parent_id = row[0]
            result['gideon_found'] = True
            result['gideon_id'] = parent_id
            
            # Find children notes (type 1)
            # In Zotero schema, parentItemID is in items table
            c.execute(\"SELECT items.itemID, itemNotes.note, items.dateModified FROM items JOIN itemNotes ON items.itemID = itemNotes.itemID WHERE items.parentItemID = ? AND items.itemTypeID = 1\", (parent_id,))
            rows = c.fetchall()
            
            result['note_count'] = len(rows)
            for r in rows:
                result['notes'].append({
                    'id': r[0],
                    'content': r[1],
                    'date_modified': r[2]
                })
        
        conn.close()
    except Exception as e:
        result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="