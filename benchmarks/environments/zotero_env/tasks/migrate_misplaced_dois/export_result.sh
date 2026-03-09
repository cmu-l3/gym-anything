#!/bin/bash
echo "=== Exporting migrate_misplaced_dois result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export DB state to JSON using python
python3 << 'PYEOF'
import sqlite3
import json
import os
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
output_path = "/tmp/task_result.json"

targets = [
    {
        "title": "Attention Is All You Need",
        "expected_doi": "10.5555/3295222.3295349"
    },
    {
        "title": "Deep Learning",
        "expected_doi": "10.1038/nature14539"
    },
    {
        "title": "ImageNet Classification with Deep Convolutional Neural Networks",
        "expected_doi": "10.5555/2999134.2999257"
    }
]

result = {
    "task_end": int(time.time()),
    "items": [],
    "app_running": False
}

try:
    # Check if app is running
    status = os.system("pgrep -f zotero > /dev/null")
    result["app_running"] = (status == 0)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get field IDs
    cursor.execute("SELECT fieldID FROM fields WHERE fieldName='DOI'")
    res = cursor.fetchone()
    doi_field_id = res[0] if res else 59

    cursor.execute("SELECT fieldID FROM fields WHERE fieldName='extra'")
    res = cursor.fetchone()
    extra_field_id = res[0] if res else 26

    for t in targets:
        item_res = {
            "title": t['title'],
            "expected_doi": t['expected_doi'],
            "found": False,
            "current_doi": None,
            "current_extra": None
        }

        # Find item
        cursor.execute("""
            SELECT i.itemID 
            FROM items i 
            JOIN itemData d ON i.itemID=d.itemID 
            JOIN itemDataValues v ON d.valueID=v.valueID 
            WHERE d.fieldID=1 AND v.value=?
        """, (t['title'],))
        
        row = cursor.fetchone()
        if row:
            item_id = row[0]
            item_res["found"] = True
            
            # Get current DOI
            cursor.execute("""
                SELECT v.value 
                FROM itemData d 
                JOIN itemDataValues v ON d.valueID=v.valueID 
                WHERE d.itemID=? AND d.fieldID=?
            """, (item_id, doi_field_id))
            doi_row = cursor.fetchone()
            if doi_row:
                item_res["current_doi"] = doi_row[0]

            # Get current Extra
            cursor.execute("""
                SELECT v.value 
                FROM itemData d 
                JOIN itemDataValues v ON d.valueID=v.valueID 
                WHERE d.itemID=? AND d.fieldID=?
            """, (item_id, extra_field_id))
            extra_row = cursor.fetchone()
            if extra_row:
                item_res["current_extra"] = extra_row[0]

        result["items"].append(item_res)

    conn.close()

except Exception as e:
    result["error"] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

print("Exported JSON result.")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="