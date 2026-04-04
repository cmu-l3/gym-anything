#!/bin/bash
echo "=== Exporting edit_case_metadata results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get Database Path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    # Fallback search
    DB_PATH=$(find /home/ga -name "jurism.sqlite" -o -name "zotero.sqlite" | head -n 1)
fi

if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    cat > /tmp/task_result.json << EOF
{
    "error": "Database not found",
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF
    exit 0
fi

# Extract data using Python for JSON formatting reliability
python3 -c "
import sqlite3
import json
import os
import datetime

db_path = '$DB_PATH'
task_start = $TASK_START
result = {
    'task_start': task_start,
    'item_found': False,
    'date_decided': None,
    'extra_field': None,
    'modified_timestamp': 0,
    'modified_during_task': False,
    'screenshot_path': '/tmp/task_final.png'
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Find Tinker item (fieldID 58 = caseName)
    cursor.execute('''
        SELECT i.itemID, strftime('%s', i.dateModified)
        FROM items i 
        JOIN itemData id ON i.itemID = id.itemID 
        JOIN itemDataValues idv ON id.valueID = idv.valueID 
        WHERE id.fieldID = 58 AND idv.value LIKE '%Tinker%'
        LIMIT 1
    ''')
    row = cursor.fetchone()

    if row:
        item_id = row[0]
        mod_time = int(row[1]) if row[1] else 0
        
        result['item_found'] = True
        result['modified_timestamp'] = mod_time
        
        # Check if modified after task start
        if mod_time >= task_start:
            result['modified_during_task'] = True
            
        # Get Date Decided (fieldID 69)
        cursor.execute('''
            SELECT idv.value 
            FROM itemData id 
            JOIN itemDataValues idv ON id.valueID = idv.valueID 
            WHERE id.itemID = ? AND id.fieldID = 69
        ''', (item_id,))
        date_row = cursor.fetchone()
        if date_row:
            result['date_decided'] = date_row[0]
            
        # Get Extra (fieldID 18)
        cursor.execute('''
            SELECT idv.value 
            FROM itemData id 
            JOIN itemDataValues idv ON id.valueID = idv.valueID 
            WHERE id.itemID = ? AND id.fieldID = 18
        ''', (item_id,))
        extra_row = cursor.fetchone()
        if extra_row:
            result['extra_field'] = extra_row[0]

    conn.close()

except Exception as e:
    result['error'] = str(e)

# Write result to temp file then move
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(result, f)
"

# Safe move of result file
mv /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json