#!/bin/bash
echo "=== Exporting fix_author_field_structure result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/task_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# Query the state of the target authors
# We look for creators linked to items with specific titles
# Note: fieldID 1 is Title

echo "Querying database for target authors..."

# We need a complex query to join items -> creators and filter by item title
# Python is easier for this JSON construction
python3 <<PYEOF > /tmp/task_result.json
import sqlite3
import json
import os
import time

db_path = "$JURISM_DB"
task_start = $TASK_START
task_end = $TASK_END

results = {
    "task_start": task_start,
    "task_end": task_end,
    "screenshot_path": "/tmp/task_final.png",
    "targets": []
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Target items to check
    targets = [
        {"fragment": "Constitutional Fact Review", "id": "monaghan"},
        {"fragment": "The Due Process Clause", "id": "poe"}
    ]
    
    for target in targets:
        # 1. Find Item ID based on title
        cursor.execute('''
            SELECT items.itemID 
            FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE itemData.fieldID = 1 AND itemDataValues.value LIKE ?
            LIMIT 1
        ''', ('%' + target["fragment"] + '%',))
        
        row = cursor.fetchone()
        if not row:
            results["targets"].append({
                "id": target["id"],
                "found": False,
                "reason": "Item not found in library"
            })
            continue
            
        item_id = row[0]
        
        # 2. Find Creator info for this item
        # We want the creator linked to this item.
        # Note: fieldMode 0 = Two-field, 1 = Single-field
        cursor.execute('''
            SELECT c.firstName, c.lastName, c.fieldMode
            FROM creators c
            JOIN itemCreators ic ON c.creatorID = ic.creatorID
            WHERE ic.itemID = ?
            ORDER BY ic.orderIndex ASC
            LIMIT 1
        ''', (item_id,))
        
        creator_row = cursor.fetchone()
        if not creator_row:
             results["targets"].append({
                "id": target["id"],
                "found": True,
                "has_creator": False,
                "reason": "No creator found for item"
            })
             continue
             
        results["targets"].append({
            "id": target["id"],
            "found": True,
            "has_creator": True,
            "first_name": creator_row[0],
            "last_name": creator_row[1],
            "field_mode": creator_row[2]
        })

    conn.close()
    
except Exception as e:
    results["error"] = str(e)

print(json.dumps(results, indent=2))
PYEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="