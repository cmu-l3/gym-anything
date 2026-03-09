#!/bin/bash
echo "=== Exporting add_isbn_to_books result ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract Book Data with ISBNs
# We need to join items, itemData (title), itemData (ISBN)
# This script creates a JSON with the current state of books in the library

python3 << PYEOF
import sqlite3
import json
import re

db_path = "$DB_PATH"
output_path = "/tmp/task_result.json"
start_time = $TASK_START

result = {
    "task_start": start_time,
    "books": [],
    "total_books_found": 0,
    "books_with_isbn": 0
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Get Field IDs
    c.execute("SELECT fieldID FROM fields WHERE fieldName='title'")
    title_fid = c.fetchone()[0]
    
    c.execute("SELECT fieldID FROM fields WHERE fieldName='ISBN'")
    isbn_fid = c.fetchone()[0]
    
    # Query for all books (itemTypeID=2)
    query = f"""
    SELECT i.itemID, 
           (SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.itemID=i.itemID AND d.fieldID={title_fid}) as title,
           (SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.itemID=i.itemID AND d.fieldID={isbn_fid}) as isbn,
           i.dateModified
    FROM items i
    WHERE i.itemTypeID=2
    """
    
    c.execute(query)
    rows = c.fetchall()
    
    for row in rows:
        item_id = row[0]
        title = row[1]
        isbn = row[2]
        date_mod = row[3] # String timestamp usually
        
        book_info = {
            "title": title,
            "isbn": isbn if isbn else None,
            "modified": date_mod
        }
        
        result["books"].append(book_info)
        
        if isbn:
            result["books_with_isbn"] += 1
            
    result["total_books_found"] = len(result["books"])
    
    conn.close()

except Exception as e:
    result["error"] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(result['books'])} books to {output_path}")
PYEOF

# Move to safe location with permissions
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="