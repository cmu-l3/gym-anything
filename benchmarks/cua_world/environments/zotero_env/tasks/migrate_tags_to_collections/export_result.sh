#!/bin/bash
# Export result for migrate_tags_to_collections task

echo "=== Exporting migrate_tags_to_collections result ==="

DB="/home/ga/Zotero/zotero.sqlite"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Give Zotero a moment to flush writes (SQLite WAL mode)
sleep 2

# Use Python to analyze the DB state against expected IDs
python3 << 'PYEOF'
import sqlite3
import json
import os

DB = "/home/ga/Zotero/zotero.sqlite"
EXPECTED_IDS_FILE = "/tmp/expected_migration_ids.json"

result = {
    "collections_created": {},
    "items_correctly_moved": {},
    "tags_removed": {},
    "errors": []
}

try:
    # Load what we expect
    if os.path.exists(EXPECTED_IDS_FILE):
        with open(EXPECTED_IDS_FILE) as f:
            expected_map = json.load(f)
    else:
        expected_map = {"dataset-mnist": [], "dataset-imagenet": []}
        result["errors"].append("Expected IDs file missing")

    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    # Check each migration target
    for tag_name, target_item_ids in expected_map.items():
        # 1. Check if Collection exists
        cur.execute("SELECT collectionID FROM collections WHERE collectionName = ?", (tag_name,))
        col_row = cur.fetchone()
        
        if col_row:
            col_id = col_row[0]
            result["collections_created"][tag_name] = True
            
            # 2. Check if expected items are in this collection
            # Get actual items in collection
            cur.execute("SELECT itemID FROM collectionItems WHERE collectionID = ?", (col_id,))
            actual_items = [r[0] for r in cur.fetchall()]
            
            # Verify specific targets
            missing = [i for i in target_item_ids if i not in actual_items]
            result["items_correctly_moved"][tag_name] = (len(missing) == 0)
        else:
            result["collections_created"][tag_name] = False
            result["items_correctly_moved"][tag_name] = False

        # 3. Check if Tag is removed
        # A tag is effectively removed if it's gone from 'tags' table 
        # OR if it exists but has 0 items in 'itemTags'
        cur.execute("SELECT tagID FROM tags WHERE name = ?", (tag_name,))
        tag_row = cur.fetchone()
        
        if not tag_row:
            result["tags_removed"][tag_name] = True
        else:
            tag_id = tag_row[0]
            cur.execute("SELECT COUNT(*) FROM itemTags WHERE tagID = ?", (tag_id,))
            count = cur.fetchone()[0]
            # If tag exists but usage is 0, we can accept it, though typically 'delete tag' removes it from tags table
            # However, Zotero logic might vary. Strict removal is preferred.
            if count == 0:
                result["tags_removed"][tag_name] = True
            else:
                result["tags_removed"][tag_name] = False

    conn.close()

except Exception as e:
    result["errors"].append(str(e))

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="