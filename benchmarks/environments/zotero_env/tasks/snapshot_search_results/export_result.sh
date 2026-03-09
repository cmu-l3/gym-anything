#!/bin/bash
# Export result for snapshot_search_results task

echo "=== Exporting results ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to run python script for complex DB extraction
python3 << 'PYEOF'
import sqlite3
import json
import os

db_path = "/home/ga/Zotero/zotero.sqlite"
output_path = "/tmp/task_result.json"
target_collection = "Theoretical Foundations"
target_keyword = "Theory"

result = {
    "collection_exists": False,
    "is_saved_search": False,
    "collection_id": None,
    "items_in_collection": [],
    "ground_truth_items": [],
    "extra_collections": []
}

try:
    if os.path.exists(db_path):
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()

        # 1. Check if collection exists in standard collections
        cur.execute("SELECT collectionID, collectionName FROM collections WHERE collectionName = ?", (target_collection,))
        row = cur.fetchone()
        if row:
            result["collection_exists"] = True
            result["collection_id"] = row[0]
        
        # 2. Check if it exists as a Saved Search (Anti-gaming)
        cur.execute("SELECT savedSearchID, savedSearchName FROM savedSearches WHERE savedSearchName = ?", (target_collection,))
        search_row = cur.fetchone()
        if search_row:
            result["is_saved_search"] = True
        
        # 3. Get items currently in the collection (if it exists)
        if result["collection_exists"]:
            # Join collectionItems -> items -> itemData (Title fieldID=1)
            cur.execute("""
                SELECT v.value 
                FROM collectionItems ci
                JOIN items i ON ci.itemID = i.itemID
                JOIN itemData d ON i.itemID = d.itemID
                JOIN itemDataValues v ON d.valueID = v.valueID
                WHERE ci.collectionID = ? 
                AND d.fieldID = 1
                AND i.itemTypeID NOT IN (1, 14)
            """, (result["collection_id"],))
            result["items_in_collection"] = [r[0] for r in cur.fetchall()]

        # 4. Get Ground Truth: All items in DB with "Theory" in title
        cur.execute("""
            SELECT v.value
            FROM items i
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.fieldID = 1
            AND i.itemTypeID NOT IN (1, 14)
            AND v.value LIKE ?
        """, (f"%{target_keyword}%",))
        result["ground_truth_items"] = [r[0] for r in cur.fetchall()]

        # 5. List other collections (debug info)
        cur.execute("SELECT collectionName FROM collections")
        result["extra_collections"] = [r[0] for r in cur.fetchall()]

        conn.close()

except Exception as e:
    result["error"] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Set permissions so host can read
chmod 644 /tmp/task_result.json

echo "Export complete. Content of JSON:"
cat /tmp/task_result.json