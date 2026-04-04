#!/bin/bash
echo "=== Exporting create_standalone_research_notes results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to query Zotero DB and analyze notes
# We use Python here because Zotero notes are HTML and we need text processing
python3 << 'PYEOF'
import sqlite3
import json
import re
import html
import os

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
TASK_START = int(os.environ.get("TASK_START", 0))

def clean_html(raw_html):
    if not raw_html: return ""
    cleanr = re.compile('<.*?>')
    text = re.sub(cleanr, ' ', raw_html)
    text = html.unescape(text)
    return ' '.join(text.split())

result = {
    "collection_exists": False,
    "collection_id": None,
    "notes": []
}

try:
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # 1. Check for Collection
    cur.execute("SELECT collectionID FROM collections WHERE collectionName = 'Dissertation Notes' AND parentCollectionID IS NULL")
    row = cur.fetchone()
    if row:
        result["collection_exists"] = True
        result["collection_id"] = row[0]
        coll_id = row[0]

    # 2. Get all Standalone Notes (itemTypeID=28 is note, parentItemID IS NULL means standalone)
    # Zotero 7 schema: items table joins with itemNotes
    # Note: timestamp check is approximate via dateAdded or dateModified strings, 
    # but we will rely on content verification mostly.
    
    cur.execute("""
        SELECT i.itemID, n.note, i.dateAdded 
        FROM items i 
        JOIN itemNotes n ON i.itemID = n.itemID 
        WHERE i.itemTypeID = 28 AND n.parentItemID IS NULL
    """)
    
    notes = cur.fetchall()
    
    for item_id, raw_note, date_added in notes:
        text_content = clean_html(raw_note)
        
        # Check if this note is in the target collection
        in_collection = False
        if result["collection_id"]:
            cur.execute("SELECT 1 FROM collectionItems WHERE collectionID=? AND itemID=?", (result["collection_id"], item_id))
            if cur.fetchone():
                in_collection = True

        result["notes"].append({
            "item_id": item_id,
            "content_text": text_content,
            "length": len(text_content),
            "in_collection": in_collection
        })

    conn.close()

except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete."
cat /tmp/task_result.json