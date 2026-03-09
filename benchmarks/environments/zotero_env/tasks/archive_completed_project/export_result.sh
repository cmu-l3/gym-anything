#!/bin/bash
echo "=== Exporting archive_completed_project results ==="

DB="/home/ga/Zotero/zotero.sqlite"
EXPORT_FILE="/home/ga/Documents/neurips_archive.ris"
TARGET_IDS_FILE="/tmp/target_item_ids.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check export file
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_FILE")
    FILE_MTIME=$(stat -c%Y "$EXPORT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Query DB for state verification using Python
python3 << PYEOF
import sqlite3
import json
import os

DB_PATH = "$DB"
TARGET_IDS_FILE = "$TARGET_IDS_FILE"
COLLECTION_NAME = "NeurIPS 2023 Draft"
TAG_NAME = "submitted-2023"

result = {
    "collection_deleted": False,
    "items_tagged": 0,
    "items_preserved": 0,
    "total_targets": 0,
    "target_ids": [],
    "tag_found_in_db": False
}

try:
    # Read target IDs
    if os.path.exists(TARGET_IDS_FILE):
        with open(TARGET_IDS_FILE, 'r') as f:
            target_ids = [int(line.strip()) for line in f if line.strip()]
        result["target_ids"] = target_ids
        result["total_targets"] = len(target_ids)
    
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    
    # Check 1: Is collection deleted?
    cur.execute("SELECT collectionID FROM collections WHERE collectionName=?", (COLLECTION_NAME,))
    col_row = cur.fetchone()
    if not col_row:
        result["collection_deleted"] = True
    
    # Check 2: Are items tagged?
    # First find the tagID for 'submitted-2023'
    cur.execute("SELECT tagID FROM tags WHERE name=?", (TAG_NAME,))
    tag_row = cur.fetchone()
    
    if tag_row:
        result["tag_found_in_db"] = True
        tag_id = tag_row[0]
        
        tagged_count = 0
        preserved_count = 0
        
        for item_id in result["target_ids"]:
            # Check tag
            cur.execute("SELECT 1 FROM itemTags WHERE itemID=? AND tagID=?", (item_id, tag_id))
            if cur.fetchone():
                tagged_count += 1
            
            # Check preservation (not in deletedItems)
            cur.execute("SELECT 1 FROM items WHERE itemID=? AND itemID NOT IN (SELECT itemID FROM deletedItems)", (item_id,))
            if cur.fetchone():
                preserved_count += 1
                
        result["items_tagged"] = tagged_count
        result["items_preserved"] = preserved_count
    
    conn.close()

except Exception as e:
    result["error"] = str(e)

# Write result to temp file
with open("/tmp/db_check.json", "w") as f:
    json.dump(result, f)
PYEOF

# Merge checks into final JSON
DB_RESULT=$(cat /tmp/db_check.json)

# Construct final JSON safely
cat > /tmp/task_result.json << EOF
{
    "export_file_exists": $FILE_EXISTS,
    "export_file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "db_checks": $DB_RESULT
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="