#!/bin/bash
echo "=== Exporting catalog_non_traditional_materials result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to robustly query the SQLite database with joins
# This avoids hardcoding IDs and handles schema relationships cleanly
python3 << 'PYEOF'
import sqlite3
import json
import os
import sys

db_path = "/home/ga/Zotero/zotero.sqlite"
output_path = "/tmp/task_result.json"
task_start = int(os.environ.get('TASK_START', 0))

result = {
    "collection_found": False,
    "collection_id": None,
    "items_found": [],
    "task_start": task_start
}

try:
    if not os.path.exists(db_path):
        raise FileNotFoundError("Zotero database not found")

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # 1. Check if collection exists
    cur.execute("SELECT collectionID FROM collections WHERE collectionName = 'Reproducibility Data'")
    col_row = cur.fetchone()

    if col_row:
        result["collection_found"] = True
        result["collection_id"] = col_row["collectionID"]

        # 2. Get items in this collection
        # We join items -> itemTypes to get the type name
        # We join itemData -> fields/values to get metadata
        query = """
            SELECT i.itemID, it.typeName, f.fieldName, v.value
            FROM collectionItems ci
            JOIN items i ON ci.itemID = i.itemID
            JOIN itemTypes it ON i.itemTypeID = it.itemTypeID
            LEFT JOIN itemData id ON i.itemID = id.itemID
            LEFT JOIN fields f ON id.fieldID = f.fieldID
            LEFT JOIN itemDataValues v ON id.valueID = v.valueID
            WHERE ci.collectionID = ?
        """
        cur.execute(query, (result["collection_id"],))
        rows = cur.fetchall()

        # Group by item
        items_map = {}
        for row in rows:
            iid = row["itemID"]
            if iid not in items_map:
                items_map[iid] = {
                    "itemID": iid,
                    "type": row["typeName"],
                    "fields": {}
                }
            if row["fieldName"] and row["value"]:
                items_map[iid]["fields"][row["fieldName"]] = row["value"]

        result["items_found"] = list(items_map.values())

    conn.close()

except Exception as e:
    result["error"] = str(e)

with open(output_path, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to allow copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json