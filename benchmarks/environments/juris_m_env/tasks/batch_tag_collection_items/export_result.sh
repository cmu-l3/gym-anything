#!/bin/bash
echo "=== Exporting batch_tag_collection_items result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

source /workspace/scripts/task_utils.sh

# Get database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Create failure result
    cat > /tmp/task_result.json << EOF
{
    "error": "Database not found",
    "passed": false
}
EOF
    exit 1
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Query the database to verify state
# We use Python to structure the complex queries clearly
python3 -c "
import sqlite3
import json
import os
import time

db_path = '$DB_PATH'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'collection_exists': False,
    'tag_exists': False,
    'items_checked': [],
    'all_tagged': False,
    'initial_tag_links': 0,
    'final_tag_links': 0
}

# 1. Get initial count
try:
    with open('/tmp/initial_tag_link_count.txt', 'r') as f:
        result['initial_tag_links'] = int(f.read().strip())
except:
    pass

cursor.execute('SELECT COUNT(*) FROM itemTags')
result['final_tag_links'] = cursor.fetchone()[0]

# 2. Check Collection
coll_name = 'Liberty & Due Process'
cursor.execute('SELECT collectionID FROM collections WHERE collectionName = ?', (coll_name,))
coll_row = cursor.fetchone()
if coll_row:
    result['collection_exists'] = True
    coll_id = coll_row[0]
else:
    coll_id = None

# 3. Check Tag
tag_name = 'due-process'
cursor.execute('SELECT tagID FROM tags WHERE name = ?', (tag_name,))
tag_row = cursor.fetchone()
tag_id = tag_row[0] if tag_row else None
if tag_id:
    result['tag_exists'] = True

# 4. Check Items in Collection
target_cases = ['Gideon v. Wainwright', 'Miranda v. Arizona', 'Obergefell v. Hodges']
all_tagged = True

if coll_id:
    # Get all items in the collection
    cursor.execute('''
        SELECT i.itemID, v.value 
        FROM collectionItems ci
        JOIN items i ON ci.itemID = i.itemID
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues v ON id.valueID = v.valueID
        WHERE ci.collectionID = ? AND id.fieldID = 58
    ''', (coll_id,))
    
    collection_items = cursor.fetchall()
    
    # We only care about checking the specific targets we added
    for target in target_cases:
        item_status = {
            'name': target,
            'in_collection': False,
            'has_tag': False
        }
        
        # Find itemID for this target
        # Use simple substring match matching setup logic
        item_id = None
        for cid, cname in collection_items:
            if target in cname:
                item_id = cid
                item_status['in_collection'] = True
                break
        
        if item_id and tag_id:
            # Check if linked to tag
            cursor.execute('SELECT COUNT(*) FROM itemTags WHERE itemID = ? AND tagID = ?', (item_id, tag_id))
            if cursor.fetchone()[0] > 0:
                item_status['has_tag'] = True
            else:
                all_tagged = False
        else:
            all_tagged = False
            
        result['items_checked'].append(item_status)
else:
    all_tagged = False

result['all_tagged'] = all_tagged

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

conn.close()
"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="