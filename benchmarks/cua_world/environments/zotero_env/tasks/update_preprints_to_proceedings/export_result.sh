#!/bin/bash
echo "=== Exporting task results ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to query DB and export structured JSON
python3 << PYEOF
import sqlite3
import json
import os

db_path = "$DB"
task_start = int("$TASK_START")

results = {
    "task_start": task_start,
    "papers": []
}

targets = [
    "Attention Is All You Need",
    "Deep Residual Learning for Image Recognition",
    "Generative Adversarial Nets"
]

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    for title in targets:
        paper_info = {
            "title": title,
            "found": False,
            "itemTypeID": None,
            "proceedingsTitle": None,
            "publicationTitle": None,
            "dateModified_ts": 0
        }
        
        # Find item
        cursor.execute("""
            SELECT i.itemID, i.itemTypeID, strftime('%s', i.dateModified)
            FROM items i 
            JOIN itemData d ON i.itemID = d.itemID 
            JOIN itemDataValues v ON d.valueID = v.valueID 
            WHERE d.fieldID=1 AND v.value=?
        """, (title,))
        row = cursor.fetchone()
        
        if row:
            item_id = row[0]
            paper_info["found"] = True
            paper_info["itemTypeID"] = row[1]
            paper_info["dateModified_ts"] = int(row[2]) if row[2] else 0
            
            # Get venue info (Proceedings Title = 39, Publication Title = 38)
            # Sometimes Zotero maps these differently depending on item type, so we check both common fields
            for field_id, field_name in [(39, "proceedingsTitle"), (38, "publicationTitle")]:
                cursor.execute("""
                    SELECT v.value 
                    FROM itemData d 
                    JOIN itemDataValues v ON d.valueID = v.valueID 
                    WHERE d.itemID=? AND d.fieldID=?
                """, (item_id, field_id))
                val_row = cursor.fetchone()
                if val_row:
                    paper_info[field_name] = val_row[0]
        
        results["papers"].append(paper_info)
        
    conn.close()

except Exception as e:
    results["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)
PYEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="