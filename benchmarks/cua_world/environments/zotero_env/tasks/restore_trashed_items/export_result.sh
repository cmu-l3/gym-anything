#!/bin/bash
# Export result for restore_trashed_items task

echo "=== Exporting restore_trashed_items result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Give Zotero a moment to flush DB writes
sleep 2

# Run Python script to query DB and verify state against saved IDs
python3 << 'PYEOF'
import sqlite3
import json
import os

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
DATA_FILE = "/tmp/restore_task_data.json"
RESULT_FILE = "/tmp/task_result.json"

result = {
    "restored_status": {},
    "collection_status": {},
    "collateral_damage": {},
    "counts": {
        "restored": 0,
        "organized": 0,
        "kept": 0
    }
}

try:
    if not os.path.exists(DATA_FILE):
        result["error"] = "Setup data file missing"
    else:
        with open(DATA_FILE, 'r') as f:
            setup_data = json.load(f)
            
        trashed_ids = setup_data.get("trashed_ids", {})
        keep_ids = setup_data.get("keep_ids", {})
        collection_id = setup_data.get("collection_id")
        
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        
        # 1. Check if targets are still in deletedItems
        # If COUNT is 0, it means it is NOT in deletedItems -> RESTORED (Success)
        for title, item_id in trashed_ids.items():
            cur.execute("SELECT COUNT(*) FROM deletedItems WHERE itemID = ?", (item_id,))
            is_deleted = cur.fetchone()[0] > 0
            is_restored = not is_deleted
            result["restored_status"][title] = is_restored
            if is_restored:
                result["counts"]["restored"] += 1
                
        # 2. Check if targets are in the collection
        # We need to find the collection ID again by name just in case, 
        # but using the ID from setup is safer if reliable. 
        # Let's verify collection name matches ID just to be sure.
        cur.execute("SELECT collectionID FROM collections WHERE collectionName = 'Thesis References'")
        row = cur.fetchone()
        if row:
            actual_collection_id = row[0]
            
            # Check targets
            for title, item_id in trashed_ids.items():
                cur.execute("SELECT COUNT(*) FROM collectionItems WHERE collectionID = ? AND itemID = ?", 
                           (actual_collection_id, item_id))
                in_collection = cur.fetchone()[0] > 0
                result["collection_status"][title] = in_collection
                if in_collection:
                    result["counts"]["organized"] += 1
            
            # 3. Check collateral damage (Original items should still be there)
            for title, item_id in keep_ids.items():
                cur.execute("SELECT COUNT(*) FROM collectionItems WHERE collectionID = ? AND itemID = ?", 
                           (actual_collection_id, item_id))
                still_there = cur.fetchone()[0] > 0
                result["collateral_damage"][title] = still_there
                if still_there:
                    result["counts"]["kept"] += 1
        else:
            result["error"] = "Collection 'Thesis References' not found"

        conn.close()

except Exception as e:
    result["error"] = str(e)

with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="