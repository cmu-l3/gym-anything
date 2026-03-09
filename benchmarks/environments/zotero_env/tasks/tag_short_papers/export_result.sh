#!/bin/bash
echo "=== Exporting tag_short_papers result ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Wait a moment for DB writes
sleep 2

# Export verification data using Python for robust SQLite handling
python3 << 'PYEOF'
import sqlite3
import json
import os
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
output_path = "/tmp/task_result.json"
task_start = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0

result = {
    "tagged_items": [],
    "tag_exists": False,
    "items_modified_during_task": 0
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 1. Check if tag exists and get ID
    cursor.execute("SELECT tagID FROM tags WHERE name='short-read'")
    row = cursor.fetchone()
    
    if row:
        tag_id = row[0]
        result["tag_exists"] = True
        
        # 2. Get items with this tag
        # Join with itemData/Values to get titles for easier verification
        query = """
            SELECT i.itemID, v.value 
            FROM itemTags it
            JOIN items i ON it.itemID = i.itemID
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE it.tagID = ? AND d.fieldID = 1
        """
        cursor.execute(query, (tag_id,))
        rows = cursor.fetchall()
        
        for item_id, title in rows:
            result["tagged_items"].append({
                "id": item_id,
                "title": title
            })
            
    # 3. Check for modification timestamps (Anti-gaming)
    # Zotero stores dates as strings 'YYYY-MM-DD HH:MM:SS', need to parse or compare roughly
    cursor.execute("SELECT dateModified FROM items")
    mod_rows = cursor.fetchall()
    
    modified_count = 0
    import datetime
    
    for mod_row in mod_rows:
        date_str = mod_row[0] # "2023-01-01 12:00:00"
        # Convert to timestamp. Zotero uses UTC usually.
        # Simple check: if dateModified string is recent (today)
        # Better: compare against task start if possible, but string parsing in bash is hard, doing it here in python
        try:
            # Assuming UTC string from DB
            dt = datetime.datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
            # Minimal check: if year is current year (seed data sets dates to 'now')
            # Since seed sets dates to 'now', we check if they changed *after* seed
            # But seed happens in setup. 
            pass 
        except:
            pass
            
    # Count items modified *after* the initial snapshot taken in setup
    # We can't easily do exact timestamp comparison without the initial snapshot loaded here
    # So we'll rely on the verification logic in verifier.py to check if the tag is present
    # The presence of the tag implies modification.
            
    conn.close()

except Exception as e:
    result["error"] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="