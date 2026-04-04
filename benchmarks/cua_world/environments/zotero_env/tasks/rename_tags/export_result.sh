#!/bin/bash
echo "=== Exporting rename_tags result ==="

DB="/home/ga/Zotero/zotero.sqlite"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper queries
# We need to export a comprehensive state of tags to JSON

python3 << 'PYEOF'
import sqlite3
import json
import os

db_path = "/home/ga/Zotero/zotero.sqlite"
result = {
    "tags": {},
    "old_tags_present": [],
    "total_item_tags": 0,
    "initial_item_tags": 0
}

# Load initial count
try:
    with open("/tmp/initial_itemtags_count", "r") as f:
        result["initial_item_tags"] = int(f.read().strip())
except:
    pass

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # 1. Get total association count
    c.execute("SELECT COUNT(*) FROM itemTags")
    result["total_item_tags"] = c.fetchone()[0]

    # 2. Check status of specific tags
    # Target renames
    target_new_names = [
        "machine-learning", 
        "natural-language-processing", 
        "computer-vision", 
        "information-theory", 
        "computer-science"
    ]
    
    target_old_names = ["ML", "NLP", "CV", "info theory", "comp sci"]

    # Check new tags
    for name in target_new_names:
        # Get tagID
        c.execute("SELECT tagID FROM tags WHERE name=?", (name,))
        row = c.fetchone()
        if row:
            tag_id = row[0]
            # Count items
            c.execute("SELECT COUNT(*) FROM itemTags WHERE tagID=?", (tag_id,))
            count = c.fetchone()[0]
            result["tags"][name] = {"exists": True, "count": count}
        else:
            result["tags"][name] = {"exists": False, "count": 0}

    # Check old tags (should be gone)
    for name in target_old_names:
        c.execute("SELECT tagID FROM tags WHERE name=?", (name,))
        row = c.fetchone()
        if row:
            result["old_tags_present"].append(name)

    conn.close()

except Exception as e:
    result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json