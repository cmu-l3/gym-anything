#!/bin/bash
# Export result for normalize_journal_names task

echo "=== Exporting normalize_journal_names result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Query database for current journal names
# We use Python to map the titles back to their current publication field values
python3 << 'PYEOF'
import sqlite3
import json
import os
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
output_path = "/tmp/task_result.json"

# The unique substrings to identify the 5 papers
targets = [
    "Minimum-Redundancy Codes",
    "Recursive Functions",
    "Connexion with Graphs",
    "Mathematical Theory of Communication",
    "Elementary Number Theory"
]

results = {
    "timestamp": time.time(),
    "items": {}
}

try:
    # Check modification times
    task_start = 0
    if os.path.exists("/tmp/task_start_time.txt"):
        with open("/tmp/task_start_time.txt", 'r') as f:
            task_start = int(f.read().strip())

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    for target in targets:
        # Get current Publication Title (field 38)
        cursor.execute("""
            SELECT v.value, i.dateModified
            FROM items i
            JOIN itemData d_title ON i.itemID = d_title.itemID
            JOIN itemDataValues v_title ON d_title.valueID = v_title.valueID
            JOIN itemData d_pub ON i.itemID = d_pub.itemID
            JOIN itemDataValues v_pub ON d_pub.valueID = v_pub.valueID
            WHERE d_title.fieldID = 1 
              AND v_title.value LIKE ?
              AND d_pub.fieldID = 38
        """, (f"%{target}%",))
        
        row = cursor.fetchone()
        if row:
            current_value = row[0]
            # Convert Zotero timestamp (text) to unix? Or just check if valid
            # Simpler: we check the value against expected in verifier
            results["items"][target] = current_value
        else:
            results["items"][target] = None
            
    conn.close()

except Exception as e:
    results["error"] = str(e)

# Check if Zotero is running
is_running = os.system("pgrep -f zotero > /dev/null") == 0
results["app_running"] = is_running

with open(output_path, 'w') as f:
    json.dump(results, f, indent=2)

print("Export finished.")
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Content of result JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="