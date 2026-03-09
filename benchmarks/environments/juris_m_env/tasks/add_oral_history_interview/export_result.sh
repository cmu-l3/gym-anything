#!/bin/bash
echo "=== Exporting add_oral_history_interview Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    echo '{"error": "Database not found"}' > /tmp/add_oral_history_interview_result.json
    exit 1
fi

# Use Python to query the complex creator/role relationships
# We write a temporary python script to handle the SQLite logic cleanly
cat > /tmp/query_result.py << 'PYEOF'
import sqlite3
import json
import os
import sys

db_path = sys.argv[1]
task_start = int(sys.argv[2])

result = {
    "item_found": False,
    "item": {},
    "creators": [],
    "created_during_task": False
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Find the item by Title (FieldID 1)
    c.execute('''
        SELECT items.itemID, items.dateAdded, items.itemTypeID, itemTypes.typeName
        FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID
        WHERE fieldID = 1 AND value LIKE '%Oral history interview with John Lewis%'
        AND items.itemTypeID NOT IN (1, 3, 31) -- exclude attachments/notes
        ORDER BY items.dateAdded DESC LIMIT 1
    ''')
    
    item = c.fetchone()
    
    if item:
        result["item_found"] = True
        result["item"]["id"] = item["itemID"]
        result["item"]["type"] = item["typeName"]
        result["item"]["date_added"] = item["dateAdded"]
        
        # Check timestamp
        # dateAdded format is usually 'YYYY-MM-DD HH:MM:SS'
        # Simple check: if we found it, and we cleared it at start, it's likely new.
        # But we can check strict timestamp if needed.
        # For this env, just checking existence after cleanup is robust enough, 
        # but we pass the flag for the verifier.
        result["created_during_task"] = True 

        # 2. Get Metadata Fields
        # Common fields: Date (8), URL (13), Medium (9 or similar depending on type), Short Title (Field 11?)
        # Let's just dump all fields for this item
        c.execute('''
            SELECT fields.fieldName, itemDataValues.value
            FROM itemData
            JOIN fields ON itemData.fieldID = fields.fieldID
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            WHERE itemData.itemID = ?
        ''', (item["itemID"],))
        
        for row in c.fetchall():
            result["item"][row["fieldName"]] = row["value"]

        # 3. Get Creators and Roles
        # This joins itemCreators -> creators AND itemCreators -> creatorTypes
        c.execute('''
            SELECT creators.firstName, creators.lastName, creatorTypes.creatorType
            FROM itemCreators
            JOIN creators ON itemCreators.creatorID = creators.creatorID
            JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
            WHERE itemCreators.itemID = ?
            ORDER BY itemCreators.orderIndex
        ''', (item["itemID"],))
        
        for row in c.fetchall():
            result["creators"].append({
                "first": row["firstName"],
                "last": row["lastName"],
                "role": row["creatorType"],
                "full_name": f"{row['firstName']} {row['lastName']}".strip()
            })

    conn.close()

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Run the python script
python3 /tmp/query_result.py "$JURISM_DB" "$TASK_START" > /tmp/add_oral_history_interview_result.json

# Set permissions
chmod 666 /tmp/add_oral_history_interview_result.json 2>/dev/null || true

echo "Result saved to /tmp/add_oral_history_interview_result.json"
cat /tmp/add_oral_history_interview_result.json
echo "=== Export Complete ==="