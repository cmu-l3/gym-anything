#!/bin/bash
echo "=== Exporting add_precise_publication_dates result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 3. Export data using Python for robust SQLite handling
# We query the 'date' field (fieldID=6) for the target papers
python3 << PYEOF
import sqlite3
import json
import os
import shutil

db_path = "$DB_PATH"
task_start = $TASK_START
output_file = "/tmp/task_result.json"

# Target papers to check
targets = [
    {"title": "Molecular Structure", "full_title": "Molecular Structure of Nucleic Acids"},
    {"title": "Deep Learning", "full_title": "Deep Learning"},
    {"title": "Attention Is All You Need", "full_title": "Attention Is All You Need"},
    {"title": "Mastering the Game of Go", "full_title": "Mastering the Game of Go"}
]

result_data = {
    "task_start": task_start,
    "papers": []
}

try:
    # Connect to DB (copy to temp first to avoid locks/corruption while app is running)
    temp_db = "/tmp/zotero_check.sqlite"
    shutil.copy2(db_path, temp_db)
    conn = sqlite3.connect(temp_db)
    cursor = conn.cursor()

    for target in targets:
        # 1. Find Item ID
        # Zotero 7 schema: items -> itemData -> itemDataValues
        # fieldID 1 is Title, fieldID 6 is Date
        
        query = """
            SELECT i.itemID, i.dateModified, v_date.value 
            FROM items i
            JOIN itemData d_title ON i.itemID = d_title.itemID
            JOIN itemDataValues v_title ON d_title.valueID = v_title.valueID
            LEFT JOIN itemData d_date ON i.itemID = d_date.itemID AND d_date.fieldID = 6
            LEFT JOIN itemDataValues v_date ON d_date.valueID = v_date.valueID
            WHERE d_title.fieldID = 1 
            AND v_title.value LIKE ?
            LIMIT 1
        """
        
        cursor.execute(query, ('%' + target["title"] + '%',))
        row = cursor.fetchone()
        
        paper_info = {
            "target_key": target["title"],
            "found": False,
            "date_value": None,
            "modified_timestamp": 0,
            "modified_during_task": False
        }

        if row:
            item_id, date_modified_str, date_val = row
            paper_info["found"] = True
            paper_info["date_value"] = date_val
            
            # Parse Zotero timestamp (format: YYYY-MM-DD HH:MM:SS)
            # We convert to unix timestamp for comparison
            import datetime
            try:
                dt = datetime.datetime.strptime(date_modified_str, "%Y-%m-%d %H:%M:%S")
                # Assume UTC/GMT for simplicity or system local
                ts = dt.timestamp()
                paper_info["modified_timestamp"] = ts
                if ts > task_start:
                    paper_info["modified_during_task"] = True
            except Exception as e:
                paper_info["timestamp_error"] = str(e)
                
        result_data["papers"].append(paper_info)

    conn.close()
    if os.path.exists(temp_db):
        os.remove(temp_db)

except Exception as e:
    result_data["error"] = str(e)

with open(output_file, 'w') as f:
    json.dump(result_data, f, indent=2)

print(f"Exported result to {output_file}")
PYEOF

# 4. Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="