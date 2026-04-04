#!/bin/bash
echo "=== Exporting create_standalone_note Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_standalone_count 2>/dev/null || echo "0")

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "{\"error\": "Database not found"}" > /tmp/task_result.json
    exit 1
fi

# Use Python to reliably extract the specific note we're looking for
# We look for ANY standalone note created after task start, or just the most recent one
python3 -c "
import sqlite3
import json
import os
import sys

db_path = '$JURISM_DB'
task_start = $TASK_START
initial_count = int('$INITIAL_COUNT')

result = {
    'task_start': task_start,
    'initial_count': initial_count,
    'final_count': 0,
    'note_found': False,
    'is_standalone': False,
    'content': '',
    'created_during_task': False,
    'screenshot_path': '/tmp/task_final.png'
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Count current standalone notes
    cursor.execute('SELECT COUNT(*) FROM itemNotes WHERE parentItemID IS NULL')
    result['final_count'] = cursor.fetchone()[0]
    
    # Find the most relevant note
    # We look for a standalone note (parentItemID IS NULL)
    # that matches our content keywords or is the most recently added
    cursor.execute('''
        SELECT n.note, i.dateAdded 
        FROM itemNotes n
        JOIN items i ON n.itemID = i.itemID
        WHERE n.parentItemID IS NULL
        ORDER BY i.dateAdded DESC
        LIMIT 1
    ''')
    
    row = cursor.fetchone()
    if row:
        note_content, date_added = row
        result['note_found'] = True
        result['is_standalone'] = True # By definition of query
        result['content'] = note_content
        
        # Check timestamp (dateAdded is string 'YYYY-MM-DD HH:MM:SS')
        # We'll rely on the Python verifier to parse the date string strictly,
        # but here we set a flag if we can parse it roughly
        result['date_added_str'] = date_added
        
        # Simple check: if final > initial, we likely created one
        if result['final_count'] > initial_count:
            result['created_during_task'] = True
            
except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="