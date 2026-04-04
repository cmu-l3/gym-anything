#!/bin/bash
# Export result for catalog_physical_archive_locations task

echo "=== Exporting catalog_physical_archive_locations result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper python script to query DB accurately
cat > /tmp/query_results.py << 'PYEOF'
import sqlite3
import json
import time

DB_PATH = "/home/ga/Zotero/zotero.sqlite"

def get_db_results():
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        # Get fieldID for 'callNumber'
        cursor.execute("SELECT fieldID FROM fields WHERE fieldName = 'callNumber'")
        res = cursor.fetchone()
        if not res:
            return {"error": "callNumber field not found in DB schema"}
        call_number_field_id = res['fieldID']

        # Query all items with their titles, authors, and call numbers
        # This query joins items -> itemData (title) -> itemData (callNumber) -> creators
        # It's complex, so we'll do it in steps for reliability
        
        # 1. Get all valid library items
        cursor.execute("""
            SELECT itemID FROM items 
            WHERE itemTypeID NOT IN (1, 14) -- Exclude notes and attachments
            AND libraryID = 1
            AND itemID NOT IN (SELECT itemID FROM deletedItems)
        """)
        items = [row['itemID'] for row in cursor.fetchall()]
        
        results = []
        
        for item_id in items:
            item_info = {"itemID": item_id, "title": None, "callNumber": None, "creators": []}
            
            # Get Title (fieldID 1 = title usually, but let's be safe)
            # Actually fieldID 110 is often title in Zotero 7 schema depending on item type, 
            # but standard title is fieldID=1 in standard map. 
            # Let's use the 'title' view or just generic value lookup if possible, 
            # but direct table access is safer if we look up fieldIDs.
            
            cursor.execute("""
                SELECT v.value, f.fieldName 
                FROM itemData d
                JOIN itemDataValues v ON d.valueID = v.valueID
                JOIN fields f ON d.fieldID = f.fieldID
                WHERE d.itemID = ?
            """, (item_id,))
            
            fields = cursor.fetchall()
            for f in fields:
                if f['fieldName'] == 'title':
                    item_info['title'] = f['value']
                elif f['fieldName'] == 'callNumber':
                    item_info['callNumber'] = f['value']
            
            # Get Creators (Authors)
            cursor.execute("""
                SELECT c.lastName, c.firstName
                FROM itemCreators ic
                JOIN creators c ON ic.creatorID = c.creatorID
                WHERE ic.itemID = ?
                ORDER BY ic.orderIndex
            """, (item_id,))
            creators = cursor.fetchall()
            item_info['creators'] = [f"{c['firstName']} {c['lastName']}" for c in creators]
            item_info['first_author_last'] = creators[0]['lastName'] if creators else ""
            
            # Get Modification Date
            cursor.execute("SELECT dateModified FROM items WHERE itemID = ?", (item_id,))
            mod_row = cursor.fetchone()
            item_info['dateModified'] = mod_row['dateModified'] if mod_row else ""
            
            results.append(item_info)
            
        conn.close()
        return {"items": results}
        
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    data = get_db_results()
    with open("/tmp/task_result.json", "w") as f:
        json.dump(data, f, indent=2)
PYEOF

# Run the python script
python3 /tmp/query_results.py

# Add timestamp info to the result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
APP_RUNNING=$(pgrep -f zotero > /dev/null && echo "true" || echo "false")

# Update JSON with metadata
jq --arg start "$TASK_START" --arg running "$APP_RUNNING" \
   '.meta = {"task_start": $start, "app_running": $running}' \
   /tmp/task_result.json > /tmp/task_result.json.tmp && mv /tmp/task_result.json.tmp /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="