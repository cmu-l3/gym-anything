#!/bin/bash
echo "=== Exporting standardize_page_hyphens result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Extract data using Python for JSON formatting and SQLite interaction
python3 << EOF
import sqlite3
import json
import os
import sys

db_path = "/home/ga/Zotero/zotero.sqlite"
output_path = "/tmp/task_result.json"

targets = [
    {"key": "turing", "title_frag": "On Computable Numbers"},
    {"key": "shannon", "title_frag": "A Mathematical Theory of Communication"},
    {"key": "he", "title_frag": "Deep Residual Learning"}
]

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "items": {},
    "database_cleanliness": {
        "double_hyphens_found": 0,
        "en_dashes_found": 0
    }
}

try:
    if os.path.exists(db_path):
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        
        # 1. Check specific target items
        for target in targets:
            # Get current page value and modification time
            query = """
                SELECT v.value, i.dateModified, i.clientDateModified
                FROM items i
                JOIN itemData d ON i.itemID = d.itemID
                JOIN itemDataValues v ON d.valueID = v.valueID
                JOIN itemData dt ON i.itemID = dt.itemID
                JOIN itemDataValues vt ON dt.valueID = vt.valueID
                WHERE d.fieldID = 32 -- Pages
                AND dt.fieldID = 1 -- Title
                AND vt.value LIKE ?
            """
            cur.execute(query, (f"%{target['title_frag']}%",))
            row = cur.fetchone()
            
            if row:
                result["items"][target["key"]] = {
                    "found": True,
                    "pages_value": row[0],
                    "date_modified": row[1],
                    "client_date_modified": row[2]
                }
            else:
                result["items"][target["key"]] = {
                    "found": False,
                    "pages_value": None
                }

        # 2. Global cleanliness check
        # Check for ANY pages field containing '--' or en-dash
        # FieldID 32 is pages
        clean_query = """
            SELECT COUNT(*) 
            FROM itemData d
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.fieldID = 32
            AND (v.value LIKE '%--%' OR v.value LIKE '%\u2013%')
        """
        cur.execute(clean_query)
        bad_count = cur.fetchone()[0]
        result["database_cleanliness"]["bad_format_count"] = bad_count
        
        conn.close()
    else:
        result["error"] = "Database file not found"

except Exception as e:
    result["error"] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported result to {output_path}")
EOF

# Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

cat /tmp/task_result.json
echo "=== Export complete ==="