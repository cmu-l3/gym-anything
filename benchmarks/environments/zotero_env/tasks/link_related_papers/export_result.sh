#!/bin/bash
# Export result for link_related_papers task
# Queries Zotero DB for item relations and resolves titles

echo "=== Exporting link_related_papers result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Python script to extract relations with titles
# We use Python because resolving the 'object' URI (which contains the Item Key)
# to a Title requires multiple lookups that are messy in Bash/sqlite3 CLI.
python3 << 'PYEOF'
import sqlite3
import json
import os
import re

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
OUTPUT_PATH = "/tmp/task_result.json"
START_TIME_PATH = "/tmp/task_start_time.txt"

result = {
    "relations_found": [],
    "total_relations": 0,
    "db_error": None,
    "timestamp_valid": True # Zotero doesn't timestamp relations in itemRelations table directly, so we infer from existence
}

try:
    if os.path.exists(START_TIME_PATH):
        with open(START_TIME_PATH, 'r') as f:
            start_time = int(f.read().strip())
    
    conn = sqlite3.connect(DB_PATH, timeout=10)
    cur = conn.cursor()

    # 1. Get DC:Relation Predicate ID
    cur.execute("SELECT predicateID FROM relationPredicates WHERE predicate='dc:relation'")
    row = cur.fetchone()
    if not row:
        # If no relations created yet, predicate might not exist
        result["db_error"] = "No relation predicate found (no relations created?)"
    else:
        pred_id = row[0]

        # 2. Get all relations
        # Structure: itemID (source) -> object (URI containing target Item Key)
        cur.execute(f"SELECT itemID, object FROM itemRelations WHERE predicateID={pred_id}")
        relations = cur.fetchall()
        result["total_relations"] = len(relations)

        # Helper to get title by ItemID
        def get_title_by_id(iid):
            # fieldID 1 = title in standard Zotero schema usually, but let's be safe
            # Actually Zotero 7 schema: items -> itemData -> itemDataValues
            # We assume title fieldID is 1 or 110 (short title).
            # Let's try standard title (fieldID=1)
            cur.execute("""
                SELECT v.value 
                FROM itemData d 
                JOIN itemDataValues v ON d.valueID=v.valueID 
                WHERE d.itemID=? AND d.fieldID=1
            """, (iid,))
            r = cur.fetchone()
            return r[0] if r else "Unknown Title"

        # Helper to get title by Item Key (from URI)
        def get_title_by_key(key):
            cur.execute("SELECT itemID FROM items WHERE key=?", (key,))
            r = cur.fetchone()
            if r:
                return get_title_by_id(r[0])
            return "Unknown Key"

        # 3. Resolve pairs
        for src_id, obj_uri in relations:
            # URI format: http://zotero.org/users/local/<libraryID>/items/<KEY>
            # Regex to extract key
            match = re.search(r'/items/([A-Z0-9]+)$', obj_uri)
            if match:
                target_key = match.group(1)
                
                src_title = get_title_by_id(src_id)
                tgt_title = get_title_by_key(target_key)
                
                result["relations_found"].append({
                    "source": src_title,
                    "target": tgt_title
                })

    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# Write result
with open(OUTPUT_PATH, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported {result['total_relations']} relations to {OUTPUT_PATH}")
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="