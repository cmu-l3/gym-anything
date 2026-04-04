#!/bin/bash
echo "=== Exporting group_citations_for_manuscript result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use embedded Python to robustly query SQLite and handle JSON export
# This avoids fragile bash string parsing for SQL results
python3 << 'PYEOF'
import sqlite3
import json
import os
import shutil

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
OUTPUT_PATH = "/tmp/task_result.json"

result = {
    "collection_found": False,
    "collection_name": None,
    "items": []
}

try:
    if not os.path.exists(DB_PATH):
        raise FileNotFoundError(f"Database not found at {DB_PATH}")

    # Connect to DB (read-only mode often safer, but standard connect works if app isn't locking it hard)
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    cur = conn.cursor()

    # 1. Find the specific collection
    # We look for fuzzy match or exact match, but verifier enforces exactness
    cur.execute("SELECT collectionID, collectionName FROM collections WHERE collectionName LIKE 'Manuscript 2024'")
    col_row = cur.fetchone()

    if col_row:
        result["collection_found"] = True
        result["collection_name"] = col_row[1]
        collection_id = col_row[0]

        # 2. Get items in this collection
        # We need: ItemID, Title, Date, Tag Names
        query = """
        SELECT i.itemID,
               (SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.itemID=i.itemID AND d.fieldID=1 LIMIT 1) as title,
               (SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.itemID=i.itemID AND d.fieldID=6 LIMIT 1) as date,
               GROUP_CONCAT(t.name) as tags
        FROM collectionItems ci
        JOIN items i ON ci.itemID = i.itemID
        LEFT JOIN itemTags it ON i.itemID = it.itemID
        LEFT JOIN tags t ON it.tagID = t.tagID
        WHERE ci.collectionID = ?
        GROUP BY i.itemID
        """
        
        cur.execute(query, (collection_id,))
        rows = cur.fetchall()

        for r in rows:
            item = {
                "itemID": r[0],
                "title": r[1] if r[1] else "",
                "date": r[2] if r[2] else "",
                "tags": r[3].split(",") if r[3] else []
            }
            result["items"].append(item)

    conn.close()

except Exception as e:
    result["error"] = str(e)

# Write result
with open(OUTPUT_PATH, 'w') as f:
    json.dump(result, f, indent=2)

# Set permissions so ga user or verifier can read it
os.chmod(OUTPUT_PATH, 0o666)
print(f"Exported result to {OUTPUT_PATH}")

PYEOF

echo "=== Export complete ==="