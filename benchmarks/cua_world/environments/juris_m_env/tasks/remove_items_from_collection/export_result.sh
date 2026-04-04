#!/bin/bash
echo "=== Exporting remove_items_from_collection results ==="
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/task_result.json << 'EOF'
{"error": "Database not found", "passed": false}
EOF
    exit 1
fi

# Query DB for verification state
# We use Python for complex verification logic (DB queries) to generate a clean JSON
python3 -c "
import sqlite3
import json
import sys

db_path = '$JURISM_DB'
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'screenshot_path': '/tmp/task_final.png',
    'collection_exists': False,
    'collection_item_count': 0,
    'obergefell_in_collection': True,
    'tinker_in_collection': True,
    'obergefell_in_library': False,
    'tinker_in_library': False,
    'total_library_count': 0,
    'deleted_items_count': 0
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # 1. Check Collection
    c.execute(\"SELECT collectionID FROM collections WHERE collectionName = 'Brief Research'\")
    row = c.fetchone()
    if row:
        result['collection_exists'] = True
        coll_id = row[0]
        
        # Count items in collection
        c.execute(\"SELECT COUNT(*) FROM collectionItems WHERE collectionID = ?\", (coll_id,))
        result['collection_item_count'] = c.fetchone()[0]
        
        # Check specific items in collection (Obergefell)
        c.execute('''
            SELECT COUNT(*) FROM collectionItems ci
            JOIN itemData id ON ci.itemID = id.itemID
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            WHERE ci.collectionID = ? AND id.fieldID = 58 AND idv.value LIKE '%Obergefell%'
        ''', (coll_id,))
        result['obergefell_in_collection'] = (c.fetchone()[0] > 0)

        # Check specific items in collection (Tinker)
        c.execute('''
            SELECT COUNT(*) FROM collectionItems ci
            JOIN itemData id ON ci.itemID = id.itemID
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            WHERE ci.collectionID = ? AND id.fieldID = 58 AND idv.value LIKE '%Tinker%'
        ''', (coll_id,))
        result['tinker_in_collection'] = (c.fetchone()[0] > 0)

    # 2. Check Library Integrity (Items must NOT be deleted/trashed)
    # Check Obergefell in items (and not in deletedItems)
    c.execute('''
        SELECT COUNT(*) FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        WHERE id.fieldID = 58 AND idv.value LIKE '%Obergefell%'
        AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    ''')
    result['obergefell_in_library'] = (c.fetchone()[0] > 0)
    
    # Check Tinker in items
    c.execute('''
        SELECT COUNT(*) FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        WHERE id.fieldID = 58 AND idv.value LIKE '%Tinker%'
        AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    ''')
    result['tinker_in_library'] = (c.fetchone()[0] > 0)

    # 3. General stats
    c.execute(\"SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,14,31) AND itemID NOT IN (SELECT itemID FROM deletedItems)\")
    result['total_library_count'] = c.fetchone()[0]
    
    c.execute(\"SELECT COUNT(*) FROM deletedItems\")
    result['deleted_items_count'] = c.fetchone()[0]

    conn.close()
    
except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="