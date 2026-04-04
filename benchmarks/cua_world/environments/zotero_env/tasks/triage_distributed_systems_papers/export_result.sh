#!/bin/bash
echo "=== Exporting triage_distributed_systems_papers result ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"
OUTPUT_FILE="/tmp/task_result.json"

# 1. Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if Zotero is still running
APP_RUNNING="false"
if pgrep -f "zotero" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Helper to run SQL returning JSON
# We use Python for reliable JSON formatting from SQLite to avoid dependency on sqlite3 json extension
# which might not be compiled in all environments, or complex shell escaping.

python3 << 'PY_EOF'
import sqlite3
import json
import sys

db_path = "/home/ga/Zotero/zotero.sqlite"
output_file = "/tmp/task_result.json"
app_running = sys.argv[1] == "true"

result = {
    "app_running": app_running,
    "collections": [],
    "items": []
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Get Collections: specifically looking for the target names
    cur.execute("""
        SELECT collectionID, collectionName 
        FROM collections 
        WHERE libraryID=1 
        AND collectionName IN ('Classic Systems', 'Modern Systems')
    """)
    rows = cur.fetchall()
    for row in rows:
        result["collections"].append({
            "id": row["collectionID"],
            "name": row["collectionName"]
        })

    # Get Items with Date field (fieldID=6) and their Collection memberships
    # We join items -> itemData -> itemDataValues to get the date
    # We left join collectionItems -> collections to get memberships
    query = """
        SELECT 
            i.itemID, 
            v.value as date_str,
            GROUP_CONCAT(c.collectionName) as collection_names
        FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        LEFT JOIN collectionItems ci ON i.itemID = ci.itemID
        LEFT JOIN collections c ON ci.collectionID = c.collectionID
        WHERE 
            i.itemTypeID NOT IN (1, 14) -- Exclude notes and attachments
            AND d.fieldID = 6 -- Date field
        GROUP BY i.itemID
    """
    cur.execute(query)
    item_rows = cur.fetchall()
    
    for row in item_rows:
        cols = row["collection_names"]
        col_list = cols.split(",") if cols else []
        result["items"].append({
            "itemID": row["itemID"],
            "date_str": row["date_str"],
            "collections": col_list
        })

    conn.close()

except Exception as e:
    result["error"] = str(e)

with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(result['items'])} items and {len(result['collections'])} collections.")
PY_EOF
"$APP_RUNNING"

# Permissions
chmod 666 "$OUTPUT_FILE" 2>/dev/null || true

echo "=== Export complete ==="