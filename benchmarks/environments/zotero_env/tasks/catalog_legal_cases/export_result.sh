#!/bin/bash
echo "=== Exporting catalog_legal_cases result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Define python script to extract structured data from Zotero DB
cat << 'EOF' > /tmp/extract_zotero_cases.py
import sqlite3
import json
import os
import sys

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
START_TIME_FILE = "/tmp/task_start_iso.txt"

def get_db_data():
    if not os.path.exists(DB_PATH):
        return {"error": "Database not found"}
        
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # 1. Get Item Type ID for 'case'
        cursor.execute("SELECT itemTypeID FROM itemTypes WHERE typeName = 'case'")
        row = cursor.fetchone()
        if not row:
            return {"error": "Case item type not found in schema"}
        case_type_id = row['itemTypeID']
        
        # 2. Get Field IDs for relevant metadata
        # Common fields: title (1), date (6)
        # Legal specific: court (27), docketNumber (28), reporter (29), reporterVolume (30), firstPage (31)
        # We'll fetch them dynamically to be safe
        fields_to_fetch = {
            'title': 'title',
            'court': 'court',
            'date': 'date',
            'docketNumber': 'docketNumber',
            'reporter': 'reporter',
            'reporterVolume': 'reporterVolume',
            'firstPage': 'firstPage'
        }
        
        field_ids = {}
        for key, name in fields_to_fetch.items():
            cursor.execute("SELECT fieldID FROM fields WHERE fieldName = ?", (name,))
            res = cursor.fetchone()
            if res:
                field_ids[key] = res['fieldID']
        
        # 3. Find items of type 'case' created during the session
        # Note: We'll fetch ALL cases and filter by timestamp in Python or logic
        # Zotero stores dates as strings in database usually, dateAdded is 'YYYY-MM-DD HH:MM:SS'
        
        # Get task start time
        start_time_iso = "1970-01-01 00:00:00"
        if os.path.exists(START_TIME_FILE):
            with open(START_TIME_FILE, 'r') as f:
                start_time_iso = f.read().strip()
                
        query = """
            SELECT itemID, dateAdded 
            FROM items 
            WHERE itemTypeID = ? 
            AND dateAdded >= ?
            AND itemID NOT IN (SELECT itemID FROM deletedItems)
        """
        cursor.execute(query, (case_type_id, start_time_iso))
        
        created_cases = []
        for item_row in cursor.fetchall():
            item_id = item_row['itemID']
            item_data = {
                'itemID': item_id,
                'dateAdded': item_row['dateAdded'],
                'fields': {}
            }
            
            # Fetch field values
            for field_name, field_id in field_ids.items():
                # Query itemData and itemDataValues
                # Note: Zotero schema links items -> itemData -> itemDataValues
                val_query = """
                    SELECT v.value 
                    FROM itemData d
                    JOIN itemDataValues v ON d.valueID = v.valueID
                    WHERE d.itemID = ? AND d.fieldID = ?
                """
                cursor.execute(val_query, (item_id, field_id))
                val_row = cursor.fetchone()
                if val_row:
                    item_data['fields'][field_name] = val_row['value']
                else:
                    item_data['fields'][field_name] = None
            
            created_cases.append(item_data)
            
        return {"created_cases": created_cases, "field_map": field_ids}
        
    except Exception as e:
        return {"error": str(e)}
    finally:
        if conn:
            conn.close()

if __name__ == "__main__":
    data = get_db_data()
    print(json.dumps(data, indent=2))
EOF

# Run extraction
python3 /tmp/extract_zotero_cases.py > /tmp/task_result.json

# Cleanup
rm /tmp/extract_zotero_cases.py

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="