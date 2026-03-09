#!/bin/bash
echo "=== Exporting flag_retracted_papers results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to inspect database
# We use Python because parsing Zotero's EAV schema in bash is fragile
cat << 'EOF' > /tmp/inspect_db.py
import sqlite3
import json
import sys
import os

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
TASK_START = int(sys.argv[1])

# Target papers original titles (partial match)
TARGETS = [
    {"key": "gan", "search": "Generative Adversarial Nets"},
    {"key": "dl", "search": "Deep Learning"}
]

results = {
    "task_start": TASK_START,
    "papers": {}
}

try:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    for target in TARGETS:
        search_term = target["search"]
        key = target["key"]
        
        # 1. Find item ID by searching current title OR original title
        # We search broadly because the title might have been changed by the agent
        query = """
            SELECT i.itemID, i.dateModified, v.value as title
            FROM items i
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.fieldID = 1 
            AND (v.value LIKE ? OR v.value LIKE ?)
            AND i.itemTypeID NOT IN (1, 14) -- Exclude notes/attachments
            LIMIT 1
        """
        cursor.execute(query, (f"%{search_term}%", f"%RETRACTED%{search_term}%"))
        row = cursor.fetchone()
        
        paper_data = {
            "found": False,
            "title": "",
            "tags": [],
            "extra": "",
            "modified_after_start": False
        }

        if row:
            paper_data["found"] = True
            paper_data["title"] = row["title"]
            item_id = row["itemID"]
            
            # Check modification time
            # Zotero stores dates as strings or timestamps depending on version/locale
            # But usually SQLite dateModified is 'YYYY-MM-DD HH:MM:SS'
            # We will rely on verifier to parse, or just check if it changed if easy
            # Actually, let's just grab the string.
            mod_date = row["dateModified"]
            # Simple check: if we can convert to timestamp, great. 
            # If not, the verifier might skip timestamp strictness or rely on content changes.
            paper_data["date_modified_str"] = mod_date

            # 2. Get Tags
            tag_query = """
                SELECT t.name 
                FROM itemTags it
                JOIN tags t ON it.tagID = t.tagID
                WHERE it.itemID = ?
            """
            cursor.execute(tag_query, (item_id,))
            tags = [r["name"] for r in cursor.fetchall()]
            paper_data["tags"] = tags

            # 3. Get Extra field
            # 'Extra' is typically fieldID 22, but let's be robust and look up fieldID
            extra_query = """
                SELECT v.value
                FROM itemData d
                JOIN itemDataValues v ON d.valueID = v.valueID
                JOIN fields f ON d.fieldID = f.fieldID
                WHERE d.itemID = ? AND f.fieldName = 'extra'
            """
            cursor.execute(extra_query, (item_id,))
            extra_row = cursor.fetchone()
            if extra_row:
                paper_data["extra"] = extra_row["value"]
            
        results["papers"][key] = paper_data

    conn.close()

except Exception as e:
    results["error"] = str(e)

print(json.dumps(results, indent=2))
EOF

# Execute Python script and save result
python3 /tmp/inspect_db.py "$TASK_START" > /tmp/task_result.json

# Cleanup
rm -f /tmp/inspect_db.py

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json