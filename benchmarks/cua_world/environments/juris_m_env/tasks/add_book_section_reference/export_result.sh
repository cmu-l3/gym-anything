#!/bin/bash
echo "=== Exporting add_book_section_reference Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
JURISM_DB=$(get_jurism_db)

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Create failure result
    cat > /tmp/task_result.json << EOF
{
    "error": "Database not found",
    "passed": false,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF
    exit 1
fi

# We use a Python script to query the complex Zotero/Jurism schema and export JSON directly.
# This is much more robust than parsing sqlite3 output in bash.
python3 << PY_SCRIPT
import sqlite3
import json
import os
import sys
from datetime import datetime

db_path = "$JURISM_DB"
task_start = $TASK_START
output_path = "/tmp/task_result.json"

result = {
    "task_start": task_start,
    "task_end": $TASK_END,
    "item_found": False,
    "item_details": {},
    "creators": [],
    "screenshot_path": "/tmp/task_final.png"
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Find the target item by title
    # We look for items created/modified recently with the specific title
    target_title = "Natural Law: The Modern Tradition"
    
    query = """
    SELECT I.itemID, I.dateAdded, IT.typeName 
    FROM items I
    JOIN itemTypes IT ON I.itemTypeID = IT.itemTypeID
    JOIN itemData ID ON I.itemID = ID.itemID
    JOIN itemDataValues IDV ON ID.valueID = IDV.valueID
    JOIN fields F ON ID.fieldID = F.fieldID
    WHERE IDV.value LIKE ? 
    AND F.fieldName = 'title'
    AND I.itemTypeID NOT IN (1, 3, 31) -- Exclude attachments/notes
    ORDER BY I.dateAdded DESC LIMIT 1
    """
    
    c.execute(query, (f"%{target_title}%",))
    item = c.fetchone()

    if item:
        result["item_found"] = True
        item_id = item["itemID"]
        
        # Check if created during task (allow slight clock skew or pre-creation if dateAdded isn't updated accurately)
        # We rely mostly on the fact that we cleaned it up in setup.
        # But we can export the date.
        result["item_details"]["date_added"] = item["dateAdded"]
        result["item_details"]["type"] = item["typeName"]
        
        # Get all fields for this item
        fields_query = """
        SELECT F.fieldName, IDV.value
        FROM itemData ID
        JOIN fields F ON ID.fieldID = F.fieldID
        JOIN itemDataValues IDV ON ID.valueID = IDV.valueID
        WHERE ID.itemID = ?
        """
        c.execute(fields_query, (item_id,))
        for row in c.fetchall():
            result["item_details"][row["fieldName"]] = row["value"]
            
        # Get creators
        creators_query = """
        SELECT C.firstName, C.lastName, CT.creatorType
        FROM itemCreators IC
        JOIN creators C ON IC.creatorID = C.creatorID
        JOIN creatorTypes CT ON IC.creatorTypeID = CT.creatorTypeID
        WHERE IC.itemID = ?
        ORDER BY IC.orderIndex
        """
        c.execute(creators_query, (item_id,))
        for row in c.fetchall():
            result["creators"].append({
                "firstName": row["firstName"],
                "lastName": row["lastName"],
                "role": row["creatorType"]
            })

    conn.close()

except Exception as e:
    result["error"] = str(e)

# Write result to JSON
with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported result to {output_path}")
PY_SCRIPT

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="