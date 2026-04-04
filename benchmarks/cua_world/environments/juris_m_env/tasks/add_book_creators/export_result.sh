#!/bin/bash
echo "=== Exporting add_book_creators result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get DB path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

TARGET_TITLE="Commentaries on the Laws of England"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to extract rich data about the item and its creators
python3 -c "
import sqlite3
import json
import os
import sys

db_path = '$DB_PATH'
target_title = '$TARGET_TITLE'
task_start = int($TASK_START)

result = {
    'item_found': False,
    'creators': [],
    'modified_during_task': False,
    'db_path': db_path
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Find item
    c.execute('''
        SELECT i.itemID, i.dateModified, i.clientDateModified
        FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        WHERE id.fieldID = 1 AND idv.value = ?
    ''', (target_title,))
    
    row = c.fetchone()
    
    if row:
        item_id = row[0]
        date_mod = row[1]
        client_date_mod = row[2]
        
        result['item_found'] = True
        result['item_id'] = item_id
        
        # Check timestamps (simple string comparison for safety, or parsing)
        # Jurism stores dates as YYYY-MM-DD HH:MM:SS
        # We'll rely on the verifier to parse properly, passing raw string
        result['date_modified'] = date_mod
        result['client_date_modified'] = client_date_mod

        # Get creators
        # Join with creatorTypes to get role name (author, editor, etc.)
        c.execute('''
            SELECT c.firstName, c.lastName, ct.creatorType
            FROM itemCreators ic
            JOIN creators c ON ic.creatorID = c.creatorID
            JOIN creatorTypes ct ON ic.creatorTypeID = ct.creatorTypeID
            WHERE ic.itemID = ?
            ORDER BY ic.orderIndex
        ''', (item_id,))
        
        creators = c.fetchall()
        for c_row in creators:
            result['creators'].append({
                'firstName': c_row[0],
                'lastName': c_row[1],
                'role': c_row[2]
            })
            
    conn.close()

except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="