#!/bin/bash
# Export result for add_items_by_identifier task
# Queries Zotero DB for items added during the task session

echo "=== Exporting add_items_by_identifier result ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_item_count 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Ensure Zotero flushes WAL file (checkpoint)
# We do this by running a dummy read query via sqlite3 which triggers a checkpoint if needed
sqlite3 "$DB" "PRAGMA wal_checkpoint;" >/dev/null 2>&1

# Python script to extract complex data from SQLite and format as JSON
python3 << PYEOF
import sqlite3
import json
import time

db_path = "$DB"
task_start = int("$TASK_START")
initial_count = int("$INITIAL_COUNT")

result = {
    "task_start": task_start,
    "initial_count": initial_count,
    "final_count": 0,
    "new_items": [],
    "error": None
}

try:
    conn = sqlite3.connect(db_path, timeout=10)
    cur = conn.cursor()
    
    # Get final count of bibliographic items
    cur.execute("SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14, 28) AND itemID NOT IN (SELECT itemID FROM deletedItems)")
    result["final_count"] = cur.fetchone()[0]
    
    # Find items added AFTER task start
    # Zotero stores dateAdded as text "YYYY-MM-DD HH:MM:SS" (UTC)
    # We need to convert python timestamp to SQL string for comparison, or fetch and filter
    
    query = """
    SELECT i.itemID, i.dateAdded, 
           (SELECT value FROM itemDataValues v JOIN itemData d ON v.valueID=d.valueID WHERE d.itemID=i.itemID AND d.fieldID=1) as title,
           (SELECT value FROM itemDataValues v JOIN itemData d ON v.valueID=d.valueID WHERE d.itemID=i.itemID AND d.fieldID=59) as doi,
           (SELECT lastName FROM creators c JOIN itemCreators ic ON c.creatorID=ic.creatorID WHERE ic.itemID=i.itemID ORDER BY ic.orderIndex LIMIT 1) as first_author,
           i.itemTypeID
    FROM items i
    WHERE i.itemTypeID NOT IN (1, 14, 28) 
      AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    """
    
    cur.execute(query)
    rows = cur.fetchall()
    
    for row in rows:
        item_id, date_added_str, title, doi, author, item_type = row
        
        # Parse Zotero date string to unix timestamp
        # Format: 2023-10-27 10:00:00
        try:
            # Assume UTC
            import calendar
            dt = time.strptime(date_added_str, "%Y-%m-%d %H:%M:%S")
            item_ts = calendar.timegm(dt)
        except:
            item_ts = 0
            
        # Filter for items added during task (with 5 second buffer for clock skew)
        if item_ts >= (task_start - 5):
            result["new_items"].append({
                "itemID": item_id,
                "title": title if title else "",
                "doi": doi if doi else "",
                "author": author if author else "",
                "date_added": date_added_str,
                "timestamp": item_ts
            })

    conn.close()

except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Found {len(result['new_items'])} new items.")
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="