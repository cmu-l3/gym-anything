#!/bin/bash
# Export result for delete_obsolete_tags task

echo "=== Exporting delete_obsolete_tags result ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database using Python for JSON export
# We check the existence of every tag we care about
python3 << 'PYEOF'
import sqlite3
import json
import os
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
output_path = "/tmp/task_result.json"
initial_item_count_path = "/tmp/initial_item_count.txt"
initial_tag_count_path = "/tmp/initial_tag_count.txt"

# Target lists
junk_tags = ["imported", "to-read-maybe", "uncategorized", "DUPLICATE", "_temp", "needs-review"]
good_tags = ["deep-learning", "computer-science", "information-theory", "physics", "NLP"]

result = {
    "timestamp": time.time(),
    "db_accessible": False,
    "junk_tags_status": {},
    "good_tags_status": {},
    "items_preserved": False,
    "initial_item_count": 0,
    "final_item_count": 0,
    "initial_tag_count": 0,
    "final_tag_count": 0
}

try:
    # Read initial counts
    if os.path.exists(initial_item_count_path):
        with open(initial_item_count_path, 'r') as f:
            result["initial_item_count"] = int(f.read().strip())
    
    if os.path.exists(initial_tag_count_path):
        with open(initial_tag_count_path, 'r') as f:
            result["initial_tag_count"] = int(f.read().strip())

    # Query DB
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    result["db_accessible"] = True

    # Check Junk Tags (Should NOT exist or have NO items)
    # Note: Zotero sometimes keeps tag in 'tags' table even if no items, 
    # but the tag selector usually hides empty tags. 
    # However, 'Delete Tag' removes it from 'tags' table.
    # We will check if it exists in 'tags' table.
    for tag in junk_tags:
        cursor.execute("SELECT count(*) FROM tags WHERE name=?", (tag,))
        exists = cursor.fetchone()[0] > 0
        result["junk_tags_status"][tag] = {
            "exists_in_db": exists
        }

    # Check Good Tags (Should EXIST and have items)
    for tag in good_tags:
        cursor.execute("SELECT tagID FROM tags WHERE name=?", (tag,))
        row = cursor.fetchone()
        exists = False
        item_count = 0
        if row:
            exists = True
            tag_id = row[0]
            cursor.execute("SELECT count(*) FROM itemTags WHERE tagID=?", (tag_id,))
            item_count = cursor.fetchone()[0]
        
        result["good_tags_status"][tag] = {
            "exists_in_db": exists,
            "item_count": item_count
        }

    # Check Item Count
    cursor.execute("SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14, 28) AND itemID NOT IN (SELECT itemID FROM deletedItems)")
    result["final_item_count"] = cursor.fetchone()[0]
    
    # Check total tag count
    cursor.execute("SELECT COUNT(*) FROM tags")
    result["final_tag_count"] = cursor.fetchone()[0]

    conn.close()

    # Determine item preservation
    # Allow small fluctuation? No, user shouldn't delete items.
    if result["final_item_count"] == result["initial_item_count"]:
        result["items_preserved"] = True
    else:
        # Check if difference is acceptable (e.g. maybe user added a note we didn't count correctly?)
        # But our query excludes notes. Strict equality is best for "Don't delete items".
        result["items_preserved"] = False

except Exception as e:
    result["error"] = str(e)

# Save result
with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

print("Export logic complete.")
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="