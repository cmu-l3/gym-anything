#!/bin/bash
echo "=== Exporting convert_notes_to_tags result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Analyze Database
python3 << 'PYEOF'
import sqlite3
import json
import re

db_path = "/home/ga/Zotero/zotero.sqlite"
task_start = int(open("/tmp/task_start_time.txt").read().strip())

conn = sqlite3.connect(db_path)
cur = conn.cursor()

def get_paper_info(title_pattern):
    # Get item ID
    cur.execute("""
        SELECT i.itemID FROM items i
        JOIN itemData d ON i.itemID=d.itemID
        JOIN itemDataValues v ON d.valueID=v.valueID
        WHERE d.fieldID=1 AND v.value LIKE ?
    """, (f"%{title_pattern}%",))
    res = cur.fetchone()
    if not res:
        return None
    item_id = res[0]
    
    # Get tags
    cur.execute("""
        SELECT t.name FROM tags t
        JOIN itemTags it ON t.tagID=it.tagID
        WHERE it.itemID=?
    """, (item_id,))
    tags = [r[0] for r in cur.fetchall()]
    
    # Get notes (active only, exclude deletedItems if possible, though Zotero 7 structure varies)
    # Checking itemNotes where parentItemID = item_id
    # And ensuring the note item itself is not in deletedItems
    cur.execute("""
        SELECT n.note FROM itemNotes n
        WHERE n.parentItemID=? 
        AND n.itemID NOT IN (SELECT itemID FROM deletedItems)
    """, (item_id,))
    notes = [r[0] for r in cur.fetchall()]
    
    return {
        "id": item_id,
        "tags": tags,
        "notes": notes
    }

results = {
    "urgent_1": get_paper_info("Attention Is All You Need"),
    "urgent_2": get_paper_info("Deep Learning"),
    "later_1": get_paper_info("Computing Machinery and Intelligence"),
    "control_1": get_paper_info("On the Electrodynamics of Moving Bodies"),
    "task_start": task_start,
    "timestamp": str(datetime.datetime.now())
}

import datetime
conn.close()

with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)
PYEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json