#!/bin/bash
# Export script for reclassify_item_types
# Check the Zotero DB for the item types of the target papers.

echo "=== Exporting reclassify_item_types result ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Wait a moment for DB writes if Zotero is still running
sleep 2

# We use python to query the DB because matching titles and mapping types is cleaner
# than complex bash/sqlite3 piping.
python3 << 'PYEOF'
import sqlite3
import json
import os
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
output_file = "/tmp/task_result.json"

targets = [
    {"title": "Attention Is All You Need", "expected": "conferencePaper"},
    {"title": "Deep Residual Learning for Image Recognition", "expected": "conferencePaper"},
    {"title": "ImageNet Classification", "expected": "conferencePaper"},
    {"title": "The Mathematical Theory of Communication", "expected": "book"}
]

result = {
    "timestamp": time.time(),
    "targets": {},
    "collateral_damage": 0,
    "total_items": 0,
    "db_accessible": False
}

try:
    if os.path.exists(db_path):
        conn = sqlite3.connect(db_path, timeout=10)
        cur = conn.cursor()
        result["db_accessible"] = True

        # 1. Helper to get item type name
        def get_type_name(type_id):
            cur.execute("SELECT typeName FROM itemTypes WHERE itemTypeID=?", (type_id,))
            row = cur.fetchone()
            return row[0] if row else "unknown"

        # 2. Check each target
        target_ids = []
        for t in targets:
            # Find item ID by title (fuzzy match)
            # We join items -> itemData -> itemDataValues
            # Field ID 1 is usually Title (in Zotero 5/6/7 standard schema)
            query = """
                SELECT i.itemID, i.itemTypeID 
                FROM items i
                JOIN itemData d ON i.itemID = d.itemID
                JOIN itemDataValues v ON d.valueID = v.valueID
                WHERE d.fieldID = 1 
                AND v.value LIKE ? 
                LIMIT 1
            """
            cur.execute(query, ('%' + t["title"] + '%',))
            row = cur.fetchone()
            
            target_info = {
                "found": False,
                "current_type": None,
                "expected_type": t["expected"],
                "correct": False
            }
            
            if row:
                target_info["found"] = True
                item_id, type_id = row
                target_ids.append(item_id)
                current_type = get_type_name(type_id)
                target_info["current_type"] = current_type
                
                if current_type == t["expected"]:
                    target_info["correct"] = True
            
            result["targets"][t["title"]] = target_info

        # 3. Check Collateral Damage
        # Count how many items are NOT in our target list but have been changed from 'journalArticle'
        # All items started as journalArticle.
        # We ignore notes (1), attachments (14), annotations (usually 1 or handled by type)
        # Zotero 7: note=1, attachment=14 (commonly) - but we use typeNames to be safe.
        
        ignored_types_query = "SELECT itemTypeID FROM itemTypes WHERE typeName IN ('note', 'attachment', 'annotation')"
        cur.execute(ignored_types_query)
        ignored_ids = [r[0] for r in cur.fetchall()]
        ignored_str = ",".join(map(str, ignored_ids)) if ignored_ids else "-1"
        
        target_ids_str = ",".join(map(str, target_ids)) if target_ids else "-1"
        
        # Get ID for journalArticle
        cur.execute("SELECT itemTypeID FROM itemTypes WHERE typeName='journalArticle'")
        ja_row = cur.fetchone()
        ja_id = ja_row[0] if ja_row else -1

        # Query: items that are NOT ignored types, NOT targets, and NOT journalArticle
        damage_query = f"""
            SELECT COUNT(*) FROM items 
            WHERE itemTypeID NOT IN ({ignored_str})
            AND itemID NOT IN ({target_ids_str})
            AND itemTypeID != {ja_id}
            AND itemID NOT IN (SELECT itemID FROM deletedItems)
        """
        cur.execute(damage_query)
        damage_count = cur.fetchone()[0]
        result["collateral_damage"] = damage_count

        # Total items for context
        cur.execute(f"SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN ({ignored_str}) AND itemID NOT IN (SELECT itemID FROM deletedItems)")
        result["total_items"] = cur.fetchone()[0]

        conn.close()

except Exception as e:
    result["error"] = str(e)

with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="