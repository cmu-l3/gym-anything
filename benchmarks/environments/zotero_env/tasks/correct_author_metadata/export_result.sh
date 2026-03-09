#!/bin/bash
# Export result for correct_author_metadata task

echo "=== Exporting correct_author_metadata result ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Give Zotero a moment to write to DB
sleep 2

# Use Python to extract specific creator details safely
python3 << PYEOF
import sqlite3
import json
import os

DB = "/home/ga/Zotero/zotero.sqlite"
TASK_START = int("$TASK_START")

# IDs saved during setup
try:
    vaswani_id = int(open("/tmp/vaswani_id").read().strip())
    lecun_id = int(open("/tmp/lecun_id").read().strip())
    goodfellow_id = int(open("/tmp/goodfellow_id").read().strip())
except:
    vaswani_id = 0
    lecun_id = 0
    goodfellow_id = 0

result = {
    "task_start": TASK_START,
    "vaswani": {"first": "", "last": ""},
    "lecun": {"first": "", "last": ""},
    "goodfellow": {"first": "", "last": ""},
    "modified_count": 0
}

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    # Get current values for Vaswani
    cur.execute("SELECT firstName, lastName FROM creators WHERE creatorID=?", (vaswani_id,))
    row = cur.fetchone()
    if row:
        result["vaswani"]["first"] = row[0]
        result["vaswani"]["last"] = row[1]

    # Get current values for LeCun
    cur.execute("SELECT firstName, lastName FROM creators WHERE creatorID=?", (lecun_id,))
    row = cur.fetchone()
    if row:
        result["lecun"]["first"] = row[0]
        result["lecun"]["last"] = row[1]

    # Get current values for Goodfellow
    cur.execute("SELECT firstName, lastName FROM creators WHERE creatorID=?", (goodfellow_id,))
    row = cur.fetchone()
    if row:
        result["goodfellow"]["first"] = row[0]
        result["goodfellow"]["last"] = row[1]
    
    # Check for items modified after task start
    # Zotero stores dates as strings, but dateModified is usually reliable
    # We check if any items were modified recently.
    # Note: SQLite date comparisons can be tricky, so we rely on Python parsing if needed, 
    # but a simple count of recently modified items is a good proxy for activity.
    
    # Check items linked to these creators
    # This query finds items linked to our target creators that have been modified since task start
    # We convert python timestamp to SQL string if needed, or just check 'datetime'
    
    cur.execute(f"""
        SELECT COUNT(DISTINCT i.itemID)
        FROM items i
        JOIN itemCreators ic ON i.itemID = ic.itemID
        WHERE ic.creatorID IN ({vaswani_id}, {lecun_id}, {goodfellow_id})
        AND i.dateModified > datetime({TASK_START}, 'unixepoch')
    """)
    result["modified_count"] = cur.fetchone()[0]

    conn.close()
except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="