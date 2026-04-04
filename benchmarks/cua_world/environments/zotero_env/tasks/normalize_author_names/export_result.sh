#!/bin/bash
echo "=== Exporting task results ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract author data for verification
# We need to query specific papers and get their author names
echo "Querying database for authors..."

python3 << 'EOF'
import sqlite3
import json
import os

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
TARGETS = [
    {"key": "turing_1", "title_sub": "Computable Numbers", "target_last": "Turing"},
    {"key": "turing_2", "title_sub": "Computing Machinery", "target_last": "Turing"},
    {"key": "shannon_1", "title_sub": "A Mathematical Theory", "target_last": "Shannon"},
    {"key": "shannon_2", "title_sub": "The Mathematical Theory", "target_last": "Shannon"},
    {"key": "hinton_1", "title_sub": "ImageNet Classification", "target_last": "Hinton"}
]

result = {
    "papers": {},
    "total_creators": 0,
    "db_accessible": False
}

try:
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    result["db_accessible"] = True

    # Get total creators for anti-gaming check
    c.execute("SELECT COUNT(*) FROM creators")
    result["total_creators"] = c.fetchone()[0]

    for t in TARGETS:
        # Complex join to get authors for specific paper titles
        query = """
            SELECT c.firstName, c.lastName
            FROM items i
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            JOIN itemCreators ic ON i.itemID = ic.itemID
            JOIN creators c ON ic.creatorID = c.creatorID
            WHERE d.fieldID = 1 
              AND v.value LIKE ? 
              AND c.lastName LIKE ?
        """
        c.execute(query, (f"%{t['title_sub']}%", f"%{t['target_last']}%"))
        rows = c.fetchall()
        
        # Store list of authors found (should be 1 per paper for these targets, but handle lists)
        authors = [{"first": r[0], "last": r[1]} for r in rows]
        result["papers"][t["key"]] = authors

    conn.close()

except Exception as e:
    result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete."
cat /tmp/task_result.json