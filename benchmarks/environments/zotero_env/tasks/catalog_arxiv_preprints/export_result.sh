#!/bin/bash
# Export result for catalog_arxiv_preprints task

echo "=== Exporting catalog_arxiv_preprints result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TIMESTAMP=$(date -Iseconds)

# 3. Query Database for results using Python
python3 << PYEOF
import sqlite3
import json
import os
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
task_start = int("$TASK_START")

targets = [
    {"title": "Attention Is All You Need", "key": "attention"},
    {"title": "BERT: Pre-training of Deep Bidirectional", "key": "bert"},
    {"title": "Generative Adversarial Nets", "key": "gan"}
]

result_data = {
    "task_start_timestamp": task_start,
    "papers": {}
}

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    
    # Get field IDs
    cur.execute("SELECT fieldID FROM fields WHERE fieldName='libraryCatalog'")
    res = cur.fetchone()
    cat_field_id = res[0] if res else 24
    
    cur.execute("SELECT fieldID FROM fields WHERE fieldName='callNumber'")
    res = cur.fetchone()
    call_field_id = res[0] if res else 25

    for target in targets:
        title_query = target["title"]
        paper_key = target["key"]
        
        # Find item
        cur.execute("""
            SELECT items.itemID, items.dateModified FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE itemData.fieldID = 1 AND itemDataValues.value LIKE ?
        """, (f"%{title_query}%",))
        
        row = cur.fetchone()
        
        paper_info = {
            "found": False,
            "catalog_value": None,
            "call_number_value": None,
            "modified_timestamp": 0,
            "modified_during_task": False
        }
        
        if row:
            item_id = row[0]
            # Convert Zotero timestamp (text) to unix? Or just check if modified recently
            # Zotero stores dateModified as 'YYYY-MM-DD HH:MM:SS' usually in UTC
            mod_date_str = row[1] 
            
            # Simple python parsing of sql date string to timestamp
            try:
                # Assuming UTC format in DB like "2023-10-27 10:00:00"
                import datetime
                dt = datetime.datetime.strptime(mod_date_str, "%Y-%m-%d %H:%M:%S")
                mod_ts = dt.replace(tzinfo=datetime.timezone.utc).timestamp()
            except:
                mod_ts = 0
            
            paper_info["found"] = True
            paper_info["modified_timestamp"] = mod_ts
            paper_info["modified_during_task"] = (mod_ts >= task_start)
            
            # Get Library Catalog value
            cur.execute("""
                SELECT itemDataValues.value FROM itemData 
                JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
                WHERE itemData.itemID = ? AND itemData.fieldID = ?
            """, (item_id, cat_field_id))
            val_row = cur.fetchone()
            paper_info["catalog_value"] = val_row[0] if val_row else None
            
            # Get Call Number value
            cur.execute("""
                SELECT itemDataValues.value FROM itemData 
                JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
                WHERE itemData.itemID = ? AND itemData.fieldID = ?
            """, (item_id, call_field_id))
            val_row = cur.fetchone()
            paper_info["call_number_value"] = val_row[0] if val_row else None
            
        result_data["papers"][paper_key] = paper_info
        
    conn.close()
    
    # Write result
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result_data, f, indent=2)
        
except Exception as e:
    print(f"Error querying database: {e}")
    # Write partial/error result
    with open("/tmp/task_result.json", "w") as f:
        json.dump({"error": str(e)}, f)

PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="