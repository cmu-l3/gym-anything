#!/bin/bash
echo "=== Exporting task results ==="

# Capture final screenshot for evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_item_count.txt 2>/dev/null || echo "0")

# Use Python to inspect the SQLite database reliably
# This script searches for the 3 expected items and checks their metadata
python3 << 'PYEOF'
import sqlite3
import json
import time
import os

db_path = "/home/ga/Zotero/zotero.sqlite"
task_start = int(open("/tmp/task_start_time.txt").read().strip())
initial_count = int(open("/tmp/initial_item_count.txt").read().strip())

result = {
    "task_start": task_start,
    "initial_count": initial_count,
    "final_count": 0,
    "items_found": {
        "book": {"found": False, "details": {}},
        "article": {"found": False, "details": {}},
        "conference": {"found": False, "details": {}}
    },
    "errors": []
}

try:
    if not os.path.exists(db_path):
        result["errors"].append("Database not found")
        raise Exception("DB missing")

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Get final count
    cursor.execute("SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14, 28) AND itemID NOT IN (SELECT itemID FROM deletedItems)")
    result["final_count"] = cursor.fetchone()[0]

    # Helper to get item metadata
    def get_item_metadata(item_id):
        meta = {}
        # Get Item Type
        cursor.execute("SELECT typeName FROM itemTypes WHERE itemTypeID = (SELECT itemTypeID FROM items WHERE itemID=?)", (item_id,))
        row = cursor.fetchone()
        if row: meta["type"] = row[0]
        
        # Get Fields
        cursor.execute("""
            SELECT f.fieldName, v.value 
            FROM itemData d
            JOIN fields f ON d.fieldID = f.fieldID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.itemID = ?
        """, (item_id,))
        for row in cursor.fetchall():
            meta[row[0]] = row[1]
            
        # Get Creators
        cursor.execute("""
            SELECT c.firstName, c.lastName, ic.orderIndex 
            FROM itemCreators ic
            JOIN creators c ON ic.creatorID = c.creatorID
            WHERE ic.itemID = ?
            ORDER BY ic.orderIndex
        """, (item_id,))
        creators = []
        for row in cursor.fetchall():
            creators.append({"first": row[0], "last": row[1]})
        meta["creators"] = creators
        
        # Get Date Added (check if it was created during task)
        cursor.execute("SELECT dateAdded FROM items WHERE itemID=?", (item_id,))
        row = cursor.fetchone()
        if row: meta["dateAdded"] = row[0]
        
        return meta

    # Define search criteria for the 3 items
    # We search broadly by title first, then verify details
    targets = [
        {"key": "book", "title_frag": "Structure of Scientific Revolutions"},
        {"key": "article", "title_frag": "Strength of Weak Ties"},
        {"key": "conference", "title_frag": "Anatomy of a Large-Scale"}
    ]

    for target in targets:
        # Search for item by title fragment
        # Note: fieldID 1 is usually title, but we join to be safe
        query = """
            SELECT i.itemID 
            FROM items i
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            JOIN fields f ON d.fieldID = f.fieldID
            WHERE f.fieldName = 'title' 
            AND v.value LIKE ? 
            AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
        """
        cursor.execute(query, (f"%{target['title_frag']}%",))
        rows = cursor.fetchall()
        
        # If multiple matches, find the one created during the task
        best_match = None
        for row in rows:
            item_id = row[0]
            meta = get_item_metadata(item_id)
            
            # Simple timestamp check - dateAdded is usually UTC string "YYYY-MM-DD HH:MM:SS"
            # We convert to unix timestamp for comparison
            try:
                # Zotero stores dateAdded as text
                import datetime
                dt = datetime.datetime.strptime(meta["dateAdded"], "%Y-%m-%d %H:%M:%S")
                # Assume Zotero DB time is roughly system time (UTC)
                item_ts = dt.timestamp()
                
                # Check if created after task start (minus small buffer)
                if item_ts >= (task_start - 5):
                    best_match = meta
                    break
            except Exception as e:
                # If timestamp parsing fails, we might accept it if it's the only one
                # but let's log it
                pass
        
        if best_match:
            result["items_found"][target["key"]]["found"] = True
            result["items_found"][target["key"]]["details"] = best_match

    conn.close()

except Exception as e:
    result["errors"].append(str(e))

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="