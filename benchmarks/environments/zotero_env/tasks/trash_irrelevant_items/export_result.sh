#!/bin/bash
echo "=== Exporting trash_irrelevant_items result ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to robustly query SQLite and generate JSON
# We need to check:
# 1. What is in deletedItems (Title, DateDeleted)
# 2. What is NOT in deletedItems (Remaining Library)
python3 << PYEOF
import sqlite3
import json
import time

db_path = "$DB"
task_start = int($TASK_START)
result = {
    "trashed_items": [],
    "remaining_items": [],
    "trash_count": 0,
    "remaining_count": 0,
    "timestamps_valid": True
}

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Query Trashed Items (Titles and Deletion Date)
    # FieldID 1 = Title
    query_trash = """
        SELECT v.value, di.dateDeleted
        FROM deletedItems di
        JOIN items i ON di.itemID = i.itemID
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE d.fieldID = 1
    """
    cur.execute(query_trash)
    for row in cur.fetchall():
        title = row[0]
        date_str = row[1] # ISO 8601 string usually
        result["trashed_items"].append(title)
        
        # Check timestamp (Zotero stores UTC ISO strings, e.g., '2023-10-27 10:00:00')
        # We'll just check if it's not null for now, as parsing ISO in minimal python env can be verbose
        if not date_str:
            result["timestamps_valid"] = False

    # Query Remaining Items (Items NOT in deletedItems)
    # Exclude notes (1), attachments (14)
    query_remaining = """
        SELECT v.value
        FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE i.itemID NOT IN (SELECT itemID FROM deletedItems)
          AND i.itemTypeID NOT IN (1, 14) 
          AND d.fieldID = 1
    """
    cur.execute(query_remaining)
    for row in cur.fetchall():
        result["remaining_items"].append(row[0])

    result["trash_count"] = len(result["trashed_items"])
    result["remaining_count"] = len(result["remaining_items"])
    
    conn.close()

except Exception as e:
    result["error"] = str(e)

# Save to temporary file first
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="