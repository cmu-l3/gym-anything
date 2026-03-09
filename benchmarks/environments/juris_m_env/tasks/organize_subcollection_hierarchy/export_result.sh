#!/bin/bash
echo "=== Exporting organize_subcollection_hierarchy Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/hierarchy_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    echo '{"error": "Jurism database not found"}' > /tmp/task_result.json
    exit 1
fi

# Export DB state to JSON using python for complex relationship mapping
python3 -c "
import sqlite3
import json
import os

db_path = '$JURISM_DB'
task_start = $TASK_START
result = {
    'task_start': task_start,
    'collections': [],
    'assignments': {},
    'error': None
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Get all collections and their parent/child structure
    # collectionID, collectionName, parentCollectionID
    c.execute('SELECT collectionID, collectionName, parentCollectionID FROM collections')
    rows = c.fetchall()
    
    collections_map = {} # ID -> Name
    hierarchy = []
    
    for row in rows:
        collections_map[row['collectionID']] = row['collectionName']
        hierarchy.append({
            'id': row['collectionID'],
            'name': row['collectionName'],
            'parent_id': row['parentCollectionID']
        })
    
    result['collections'] = hierarchy

    # 2. Get items in each collection
    # We need to resolve itemIDs to Titles/Case Names
    # Field 1 = title, Field 58 = caseName
    
    c.execute('''
        SELECT 
            c.collectionName, 
            v.value AS itemTitle
        FROM collectionItems ci
        JOIN collections c ON ci.collectionID = c.collectionID
        JOIN items i ON ci.itemID = i.itemID
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues v ON id.valueID = v.valueID
        WHERE i.itemTypeID NOT IN (1, 3, 31) -- Exclude attachments/notes
          AND id.fieldID IN (1, 58) -- Title or Case Name
    ''')
    
    assignments = {}
    for row in c.fetchall():
        coll = row['collectionName']
        title = row['itemTitle']
        if coll not in assignments:
            assignments[coll] = []
        assignments[coll].append(title)
        
    result['assignments'] = assignments
    
    conn.close()

except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="