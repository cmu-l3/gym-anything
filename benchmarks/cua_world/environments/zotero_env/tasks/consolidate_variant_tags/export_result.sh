#!/bin/bash
echo "=== Exporting consolidate_variant_tags result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

DB="/home/ga/Zotero/zotero.sqlite"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query DB for tag existence and counts
echo "Querying database..."

python3 << 'PYEOF'
import sqlite3
import json
import os
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
result = {
    "bad_tags_exist": {},
    "canonical_tags_exist": {},
    "canonical_tag_counts": {},
    "total_tagged_items": 0,
    "timestamp": time.time()
}

bad_tags = ["deep-learning", "deep learning", "nlp"]
canonical_tags = ["Deep Learning", "NLP"]

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Check Bad Tags
    for tag in bad_tags:
        c.execute("SELECT tagID FROM tags WHERE name=?", (tag,))
        row = c.fetchone()
        result["bad_tags_exist"][tag] = (row is not None)

    # Check Canonical Tags and Counts
    for tag in canonical_tags:
        c.execute("SELECT tagID FROM tags WHERE name=?", (tag,))
        row = c.fetchone()
        if row:
            tag_id = row[0]
            result["canonical_tags_exist"][tag] = True
            # Count items
            c.execute("SELECT COUNT(*) FROM itemTags WHERE tagID=?", (tag_id,))
            count = c.fetchone()[0]
            result["canonical_tag_counts"][tag] = count
        else:
            result["canonical_tags_exist"][tag] = False
            result["canonical_tag_counts"][tag] = 0

    conn.close()
except Exception as e:
    result["error"] = str(e)

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="