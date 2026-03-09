#!/bin/bash
# Export result for create_chronological_collections task

echo "=== Exporting create_chronological_collections result ==="

# ── 1. Capture final screenshot ───────────────────────────────────────────
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# ── 2. Query Database and Export to JSON ──────────────────────────────────
# We use Python for robust SQLite querying and JSON generation
python3 << 'PYEOF'
import sqlite3
import json
import os
import time

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
TASK_START_FILE = "/tmp/task_start_time.txt"

result = {
    "collections": [],
    "papers": [],
    "task_duration_valid": True,
    "timestamp": time.time()
}

# Check start time
try:
    if os.path.exists(TASK_START_FILE):
        with open(TASK_START_FILE, 'r') as f:
            start_time = int(f.read().strip())
            # Basic sanity check that file wasn't created in the future
            if start_time > time.time():
                result["task_duration_valid"] = False
except Exception:
    pass

try:
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # 1. Get all collections
    cur.execute("SELECT collectionID, collectionName FROM collections WHERE libraryID=1")
    collections = cur.fetchall()
    
    collection_map = {} # ID -> Name
    
    for coll in collections:
        c_id = coll["collectionID"]
        c_name = coll["collectionName"]
        collection_map[c_id] = c_name
        
        # Get items in this collection
        # We need item titles. Item title is fieldID 1 in itemData.
        # We also grab the date/year (fieldID 6) just in case, though we verify by title logic in verifier.
        query = """
            SELECT i.itemID, v_title.value AS title
            FROM collectionItems ci
            JOIN items i ON ci.itemID = i.itemID
            JOIN itemData d_title ON i.itemID = d_title.itemID AND d_title.fieldID = 1
            JOIN itemDataValues v_title ON d_title.valueID = v_title.valueID
            WHERE ci.collectionID = ?
        """
        cur.execute(query, (c_id,))
        items = cur.fetchall()
        
        item_list = [item["title"] for item in items]
        
        result["collections"].append({
            "id": c_id,
            "name": c_name,
            "items": item_list
        })

    # 2. Get all papers in library (to verify we processed everyone)
    # Exclude notes (1) and attachments (14)
    query_all = """
        SELECT i.itemID, v_title.value AS title
        FROM items i
        JOIN itemData d_title ON i.itemID = d_title.itemID AND d_title.fieldID = 1
        JOIN itemDataValues v_title ON d_title.valueID = v_title.valueID
        WHERE i.itemTypeID NOT IN (1, 14) 
        AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    """
    cur.execute(query_all)
    all_papers = cur.fetchall()
    result["papers"] = [p["title"] for p in all_papers]

    conn.close()

except Exception as e:
    result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(result['collections'])} collections and {len(result['papers'])} total papers.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="