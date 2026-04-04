#!/bin/bash
echo "=== Exporting add_missing_coauthors result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query DB and export to JSON using Python
# We need to extract the authors for our specific target papers to verify they were added.
python3 << 'PYEOF'
import sqlite3
import json
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
output_path = "/tmp/task_result.json"

targets = [
    "Attention Is All You Need",
    "Deep Residual Learning for Image Recognition",
    "Molecular Structure of Nucleic Acids",
    "Generative Adversarial Nets"
]

result = {
    "task_end_time": time.time(),
    "papers": {}
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    for title_fragment in targets:
        # Find item ID
        cursor.execute("""
            SELECT i.itemID, v.value FROM items i
            JOIN itemData d ON i.itemID=d.itemID
            JOIN itemDataValues v ON d.valueID=v.valueID
            WHERE d.fieldID=1 AND v.value LIKE ?
        """, (f"%{title_fragment}%",))
        
        row = cursor.fetchone()
        if row:
            item_id = row[0]
            full_title = row[1]
            
            # Get authors
            # CreatorTypeID 8 is 'author'
            cursor.execute("""
                SELECT c.firstName, c.lastName, ic.orderIndex
                FROM itemCreators ic
                JOIN creators c ON ic.creatorID = c.creatorID
                WHERE ic.itemID = ? AND ic.creatorTypeID = 8
                ORDER BY ic.orderIndex ASC
            """, (item_id,))
            
            authors = []
            for auth_row in cursor.fetchall():
                authors.append({
                    "firstName": auth_row[0],
                    "lastName": auth_row[1],
                    "order": auth_row[2]
                })
            
            result["papers"][title_fragment] = {
                "found": True,
                "item_id": item_id,
                "title": full_title,
                "authors": authors,
                "author_count": len(authors)
            }
        else:
            result["papers"][title_fragment] = {
                "found": False,
                "error": "Paper not found in DB"
            }

    conn.close()

except Exception as e:
    result["error"] = str(e)

with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported result to {output_path}")
PYEOF

# Set permissions so framework can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="