#!/bin/bash
# Export results for correct_item_types_to_conference task

echo "=== Exporting task results ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Data using Python/SQLite
# We need to map the specific papers to their current itemTypes and check modification times.
python3 <<PY_SCRIPT
import sqlite3
import json
import time

db_path = "$DB"
task_start = int($TASK_START)
task_end = int($TASK_END)

targets = [
    "Attention Is All You Need",
    "ImageNet Classification with Deep Convolutional Neural Networks",
    "Deep Residual Learning for Image Recognition",
    "Mastering the Game of Go with Deep Neural Networks and Tree Search"
]

results = {
    "task_start": task_start,
    "task_end": task_end,
    "papers": {}
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    for title in targets:
        # Find itemID, current itemType, and modification date
        query = """
        SELECT i.itemID, t.typeName, i.dateModified
        FROM items i
        JOIN itemTypes t ON i.itemTypeID = t.itemTypeID
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE d.fieldID = 1 AND v.value LIKE ?
        LIMIT 1
        """
        # Note: fieldID 1 is usually Title. value LIKE %title% matches the paper.
        
        cursor.execute(query, (f"%{title}%",))
        row = cursor.fetchone()
        
        if row:
            item_id, type_name, date_mod_str = row
            # Convert Zotero dateModified (string 'YYYY-MM-DD HH:MM:SS') to timestamp
            # Zotero stores times in UTC usually.
            try:
                # Basic parsing, might need adjustment for TZ, but relative comparison is key
                # Zotero SQL dates are usually 'YYYY-MM-DD HH:MM:SS'
                mod_ts = time.mktime(time.strptime(date_mod_str, "%Y-%m-%d %H:%M:%S"))
            except:
                mod_ts = 0
            
            was_modified = mod_ts > task_start

            results["papers"][title] = {
                "found": True,
                "current_type": type_name,
                "was_modified": was_modified,
                "mod_time": date_mod_str
            }
        else:
            results["papers"][title] = {
                "found": False,
                "current_type": None,
                "was_modified": False
            }

    conn.close()

except Exception as e:
    results["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)

PY_SCRIPT

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="