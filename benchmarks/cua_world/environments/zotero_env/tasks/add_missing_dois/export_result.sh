#!/bin/bash
echo "=== Exporting add_missing_dois results ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to query DB and build result JSON
# We use Python here to handle the complex join and JSON formatting reliably
python3 << 'PYEOF'
import sqlite3
import json
import os
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
task_start = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0

# Target papers to check (substrings of titles)
targets = [
    "Mathematical Theory of Communication",
    "Computing Machinery and Intelligence",
    "Molecular Structure of Nucleic Acids",
    "Deep Residual Learning for Image Recognition",
    "ImageNet Classification with Deep Convolutional Neural Networks"
]

results = {
    "task_start": task_start,
    "timestamp": time.time(),
    "app_running": os.system("pgrep -f zotero > /dev/null") == 0,
    "targets": []
}

try:
    conn = sqlite3.connect(db_path, timeout=10)
    cur = conn.cursor()

    # Query to find itemID, Title, and DOI for specific papers
    # Field 1 = Title, Field 59 = DOI
    for target in targets:
        query = """
        SELECT i.itemID, v_title.value, v_doi.value, i.dateModified
        FROM items i
        JOIN itemData d_title ON i.itemID = d_title.itemID AND d_title.fieldID = 1
        JOIN itemDataValues v_title ON d_title.valueID = v_title.valueID
        LEFT JOIN itemData d_doi ON i.itemID = d_doi.itemID AND d_doi.fieldID = 59
        LEFT JOIN itemDataValues v_doi ON d_doi.valueID = v_doi.valueID
        WHERE v_title.value LIKE ?
        LIMIT 1
        """
        cur.execute(query, (f"%{target}%",))
        row = cur.fetchone()
        
        entry = {
            "target_substring": target,
            "found": False,
            "title": None,
            "doi_value": None,
            "modified_timestamp": None
        }

        if row:
            entry["found"] = True
            entry["item_id"] = row[0]
            entry["title"] = row[1]
            entry["doi_value"] = row[2]  # Can be None if no DOI field exists
            
            # Parse modification date if available (format: YYYY-MM-DD HH:MM:SS)
            # Zotero stores times in UTC string usually
            mod_time_str = row[3]
            entry["modified_timestamp"] = mod_time_str
        
        results["targets"].append(entry)

    conn.close()

except Exception as e:
    results["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)

print(json.dumps(results, indent=2))
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="