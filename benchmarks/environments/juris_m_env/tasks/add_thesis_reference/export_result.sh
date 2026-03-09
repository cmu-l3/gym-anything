#!/bin/bash
echo "=== Exporting add_thesis_reference results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# Export data using Python to handle SQLite complexity and JSON formatting safely
python3 << EOF
import sqlite3
import json
import os
from datetime import datetime

db_path = "$JURISM_DB"
task_start = $TASK_START
result = {
    "task_start": task_start,
    "task_end": $TASK_END,
    "item_found": False,
    "item": {},
    "timestamp_valid": False
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # 1. Find the Thesis item type ID
    c.execute("SELECT itemTypeID FROM itemTypes WHERE typeName = 'thesis'")
    row = c.fetchone()
    thesis_type_id = row[0] if row else 32  # Default to 32 if not found, though usually standard
    
    # 2. Find items of type Thesis created/modified recently
    # We look for the specific title first to be sure
    query = '''
        SELECT i.itemID, i.dateAdded 
        FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        WHERE (i.itemTypeID = ? OR i.itemTypeID = (SELECT itemTypeID FROM itemTypes WHERE typeName='thesis'))
        AND LOWER(idv.value) LIKE '%symbolic analysis%'
        LIMIT 1
    '''
    c.execute(query, (thesis_type_id,))
    item_row = c.fetchone()
    
    if item_row:
        item_id, date_added = item_row
        result["item_found"] = True
        result["item"]["id"] = item_id
        result["item"]["dateAdded"] = date_added
        
        # Check timestamp (dateAdded format is usually 'YYYY-MM-DD HH:MM:SS')
        try:
            # Parse dateAdded to timestamp
            added_dt = datetime.strptime(date_added, '%Y-%m-%d %H:%M:%S')
            result["timestamp_valid"] = added_dt.timestamp() > (task_start - 60) # Tolerance of 60s
        except Exception as e:
            print(f"Date parse error: {e}")
            result["timestamp_valid"] = True # Fallback if parsing fails, assume valid if found
            
        # 3. Get all metadata fields for this item
        # We fetch fieldName and value
        c.execute('''
            SELECT f.fieldName, idv.value 
            FROM itemData id
            JOIN fields f ON id.fieldID = f.fieldID
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            WHERE id.itemID = ?
        ''', (item_id,))
        
        fields = {row[0]: row[1] for row in c.fetchall()}
        result["item"]["fields"] = fields
        
        # 4. Get creators (Author)
        c.execute('''
            SELECT c.firstName, c.lastName, ct.creatorType 
            FROM itemCreators ic
            JOIN creators c ON ic.creatorID = c.creatorID
            JOIN creatorTypes ct ON ic.creatorTypeID = ct.creatorTypeID
            WHERE ic.itemID = ?
            ORDER BY ic.orderIndex
        ''', (item_id,))
        
        creators = []
        for crow in c.fetchall():
            creators.append({
                "firstName": crow[0],
                "lastName": crow[1],
                "type": crow[2]
            })
        result["item"]["creators"] = creators
        
    conn.close()
    
except Exception as e:
    result["error"] = str(e)

# Write result to temp file then move
with open('/tmp/export_data.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Move result to final location
mv /tmp/export_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="