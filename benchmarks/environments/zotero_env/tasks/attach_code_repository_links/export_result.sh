#!/bin/bash
echo "=== Exporting attach_code_repository_links result ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to query the database and generate JSON result
# We need to check for attachments (itemTypeID=14) linked to our target papers
# and extract their URLs.

python3 << 'PYEOF'
import sqlite3
import json
import os

db_path = "/home/ga/Zotero/zotero.sqlite"
task_start = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0

targets = [
    "Attention Is All You Need",
    "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding",
    "Deep Residual Learning for Image Recognition"
]

results = {
    "task_start": task_start,
    "papers": {}
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    for title in targets:
        # 1. Find the paper ID
        cursor.execute("""
            SELECT i.itemID 
            FROM items i
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.fieldID = 1 AND v.value = ?
        """, (title,))
        
        row = cursor.fetchone()
        if not row:
            results["papers"][title] = {"found": False, "attachments": []}
            continue
            
        paper_id = row[0]
        
        # 2. Find attachments (children) for this paper
        # itemTypeID 14 is Attachment
        cursor.execute("""
            SELECT i.itemID, i.dateAdded 
            FROM items i 
            WHERE i.parentItemID = ? AND i.itemTypeID = 14
        """, (paper_id,))
        
        attachments = []
        att_rows = cursor.fetchall()
        
        for att_id, date_added in att_rows:
            # 3. Get the URL for this attachment
            # URL is usually in fieldID 13, but let's just search all fields for this item
            cursor.execute("""
                SELECT v.value 
                FROM itemData d
                JOIN itemDataValues v ON d.valueID = v.valueID
                WHERE d.itemID = ?
            """, (att_id,))
            
            vals = [r[0] for r in cursor.fetchall()]
            # Filter for things that look like URLs
            urls = [v for v in vals if v.startswith("http")]
            
            if urls:
                attachments.append({
                    "id": att_id,
                    "url": urls[0], # Assuming one URL per attachment
                    "date_added": date_added # Zotero stores this as string usually
                })
        
        results["papers"][title] = {
            "found": True,
            "id": paper_id,
            "attachments": attachments
        }
        
    conn.close()

except Exception as e:
    results["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="