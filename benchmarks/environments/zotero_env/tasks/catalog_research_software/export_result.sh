#!/bin/bash
echo "=== Exporting catalog_research_software result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Export Database Content using Python for robust schema handling
# We need to extract items of type 'computerProgram' and their metadata
python3 << 'PYEOF'
import sqlite3
import json
import os

db_path = "/home/ga/Zotero/zotero.sqlite"
output_path = "/tmp/task_result.json"

result = {
    "timestamp": "",
    "computer_programs": [],
    "app_running": False
}

try:
    # Check if app is running
    result["app_running"] = (os.system("pgrep -f zotero > /dev/null") == 0)

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Get computerProgram type ID
    cur.execute("SELECT itemTypeID FROM itemTypes WHERE typeName = 'computerProgram'")
    row = cur.fetchone()
    
    if row:
        prog_type_id = row['itemTypeID']
        
        # Get all computerProgram items
        cur.execute("""
            SELECT itemID, dateAdded, dateModified 
            FROM items 
            WHERE itemTypeID = ? AND itemID NOT IN (SELECT itemID FROM deletedItems)
        """, (prog_type_id,))
        
        items = cur.fetchall()
        
        for item in items:
            item_obj = {
                "itemID": item['itemID'],
                "dateAdded": item['dateAdded'],
                "fields": {},
                "creators": []
            }
            
            # Get Fields (Title, Version, Company, System, URL, etc.)
            # Join itemData -> fields -> itemDataValues
            cur.execute("""
                SELECT f.fieldName, v.value
                FROM itemData id
                JOIN fields f ON id.fieldID = f.fieldID
                JOIN itemDataValues v ON id.valueID = v.valueID
                WHERE id.itemID = ?
            """, (item['itemID'],))
            
            for field in cur.fetchall():
                item_obj["fields"][field['fieldName']] = field['value']
            
            # Get Creators (Programmer)
            # Join itemCreators -> creators -> creatorTypes
            cur.execute("""
                SELECT c.firstName, c.lastName, c.fieldMode, ct.creatorType
                FROM itemCreators ic
                JOIN creators c ON ic.creatorID = c.creatorID
                JOIN creatorTypes ct ON ic.creatorTypeID = ct.creatorTypeID
                WHERE ic.itemID = ?
                ORDER BY ic.orderIndex
            """, (item['itemID'],))
            
            for creator in cur.fetchall():
                item_obj["creators"].append({
                    "firstName": creator['firstName'],
                    "lastName": creator['lastName'],
                    "fieldMode": creator['fieldMode'], # 1 = single field
                    "type": creator['creatorType']
                })
                
            result["computer_programs"].append(item_obj)

    conn.close()

except Exception as e:
    result["error"] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Found $(grep -c "itemID" /tmp/task_result.json) items."