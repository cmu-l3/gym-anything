#!/bin/bash
# Export script for add_treaty_reference task
echo "=== Exporting add_treaty_reference Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Task timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    echo '{"error": "Database not found", "passed": false}' > /tmp/add_treaty_reference_result.json
    exit 1
fi

# Use Python to extract structured data from SQLite
# This is more robust than bash for handling schema joins and field mapping
python3 << EOF
import sqlite3
import json
import time
import os

db_path = "$JURISM_DB"
task_start = $TASK_START
output_file = "/tmp/add_treaty_reference_result.json"

result = {
    "task_start": task_start,
    "task_end": $TASK_END,
    "item_found": False,
    "created_during_task": False,
    "item_type": None,
    "fields": {},
    "screenshot_path": "/tmp/task_final.png"
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 1. Find the item: Look for 'Vienna Convention on the Law of Treaties'
    # We search specifically for the title field
    cursor.execute('''
        SELECT i.itemID, i.itemTypeID, i.dateAdded, idv.value
        FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        JOIN fields f ON id.fieldID = f.fieldID
        WHERE f.fieldName = 'title' 
          AND idv.value LIKE '%Vienna Convention%Law of Treaties%'
          AND i.itemTypeID NOT IN (1, 3, 14) -- Exclude attachments/notes
        ORDER BY i.dateAdded DESC LIMIT 1
    ''')
    
    row = cursor.fetchone()
    
    if row:
        item_id, type_id, date_added_str, title = row
        result["item_found"] = True
        result["fields"]["title"] = title
        
        # Check creation time (anti-gaming)
        # SQLite date format is usually "YYYY-MM-DD HH:MM:SS"
        try:
            # Parse UTC string to timestamp
            # Jurism stores dates in UTC like "2023-10-25 14:30:00"
            struct_time = time.strptime(date_added_str, "%Y-%m-%d %H:%M:%S")
            item_ts = time.mktime(struct_time)
            # Allow some clock skew tolerance
            if item_ts >= (task_start - 60):
                result["created_during_task"] = True
        except ValueError:
            # Fallback if date parsing fails
            result["created_during_task"] = False

        # 2. Get Item Type Name
        cursor.execute('SELECT typeName FROM itemTypes WHERE itemTypeID = ?', (type_id,))
        type_row = cursor.fetchone()
        if type_row:
            result["item_type"] = type_row[0]

        # 3. Get all other fields for this item
        cursor.execute('''
            SELECT f.fieldName, idv.value
            FROM itemData id
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            JOIN fields f ON id.fieldID = f.fieldID
            WHERE id.itemID = ?
        ''', (item_id,))
        
        for field_name, value in cursor.fetchall():
            result["fields"][field_name] = value

    conn.close()

except Exception as e:
    result["error"] = str(e)

# Write result to file
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported result to {output_file}")
EOF

# Ensure permissions
chmod 666 /tmp/add_treaty_reference_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/add_treaty_reference_result.json