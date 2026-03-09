#!/bin/bash
# Export result for attach_pdf_files task

echo "=== Exporting attach_pdf_files result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to query DB and export JSON
# We use Python for reliable JSON generation and complex SQLite querying
python3 << 'EOF'
import sqlite3
import json
import os
import time

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
START_TIME_FILE = "/tmp/task_start_time"
INITIAL_COUNT_FILE = "/tmp/initial_attachment_count"
OUTPUT_FILE = "/tmp/task_result.json"

result = {
    "attachments_found": [],
    "total_attachments_added": 0,
    "stored_copies_count": 0,
    "db_error": None
}

try:
    # Get task start time
    try:
        with open(START_TIME_FILE, 'r') as f:
            start_timestamp = int(f.read().strip())
    except:
        start_timestamp = 0

    # Get initial count
    try:
        with open(INITIAL_COUNT_FILE, 'r') as f:
            initial_count = int(f.read().strip())
    except:
        initial_count = 0

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Query for attachments added AFTER task start
    # We join:
    # - items (to get dateAdded and parentID)
    # - itemAttachments (to get path, contentType)
    # - itemData/Values (to get the Title of the PARENT item)
    
    query = """
    SELECT 
        parent_item.itemID,
        idv.value AS parent_title,
        ia.path,
        ia.contentType,
        ia.linkMode,
        attachment_item.dateAdded
    FROM itemAttachments ia
    JOIN items attachment_item ON ia.itemID = attachment_item.itemID
    JOIN items parent_item ON ia.parentItemID = parent_item.itemID
    -- Join to get parent title (fieldID 1 = title)
    LEFT JOIN itemData id ON parent_item.itemID = id.itemID AND id.fieldID = 1
    LEFT JOIN itemDataValues idv ON id.valueID = idv.valueID
    WHERE 
        ia.contentType = 'application/pdf'
    """
    
    cursor.execute(query)
    rows = cursor.fetchall()
    
    current_count = 0
    new_attachments = []
    
    for row in rows:
        parent_id, parent_title, path, content_type, link_mode, date_added_str = row
        
        # Parse Zotero date (YYYY-MM-DD HH:MM:SS)
        # We need to be careful with timezones, but usually comparing raw string 
        # is risky if not careful. Converting to unix timestamp is safer.
        # Zotero stores dates as UTC strings usually.
        try:
             # simplistic parsing, assuming standard format
             import datetime
             dt = datetime.datetime.strptime(date_added_str, "%Y-%m-%d %H:%M:%S")
             # Treat as UTC
             file_timestamp = dt.replace(tzinfo=datetime.timezone.utc).timestamp()
        except:
             file_timestamp = 0
        
        # Only count if added after task start (with small buffer)
        if file_timestamp >= (start_timestamp - 5):
            current_count += 1
            
            # Check if stored copy
            # linkMode: 0=imported file (stored), 1=imported url, 2=linked file, 3=linked url
            # path: starts with 'storage:' for stored files
            is_stored_copy = (link_mode == 0) and (path and path.startswith('storage:'))
            
            if is_stored_copy:
                result["stored_copies_count"] += 1

            new_attachments.append({
                "parent_title": parent_title,
                "path": path,
                "is_stored_copy": is_stored_copy,
                "date_added": date_added_str
            })

    result["attachments_found"] = new_attachments
    result["total_attachments_added"] = len(new_attachments)
    
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# Write result
with open(OUTPUT_FILE, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported result to {OUTPUT_FILE}")
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="