#!/bin/bash
echo "=== Exporting assign_call_numbers result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Get config
DB_PATH=$(get_jurism_db)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    # Create empty error result
    cat > /tmp/task_result.json << EOF
{
    "error": "Database not found",
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF
    exit 1
fi

# Query database for the status of our three target cases
# We export a JSON structure containing the current state of these items
python3 -c "
import sqlite3
import json
import os
from datetime import datetime

db_path = '$DB_PATH'
task_start = $TASK_START
output_file = '/tmp/task_result.json'

targets = [
    {'search': 'Brown v. Board', 'key': 'brown'},
    {'search': 'Miranda v. Arizona', 'key': 'miranda'},
    {'search': 'Marbury v. Madison', 'key': 'marbury'}
]

field_call_number = 14
field_case_name = 58
field_title = 1

results = {
    'task_start': task_start,
    'task_end': $TASK_END,
    'db_path': db_path,
    'items': {}
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    for target in targets:
        search_term = target['search']
        key = target['key']
        
        # Find item
        cursor.execute('''
            SELECT items.itemID, items.dateModified FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE fieldID IN (?, ?) AND value LIKE ? AND itemTypeID NOT IN (1,3,31)
            LIMIT 1
        ''', (field_case_name, field_title, f'%{search_term}%'))
        
        row = cursor.fetchone()
        if row:
            item_id = row[0]
            date_modified_str = row[1] # Format: YYYY-MM-DD HH:MM:SS
            
            # Get Call Number
            cursor.execute('''
                SELECT value FROM itemData 
                JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
                WHERE itemID = ? AND fieldID = ?
            ''', (item_id, field_call_number))
            
            cn_row = cursor.fetchone()
            call_number = cn_row[0] if cn_row else None
            
            # Check modification time vs task start
            # Parse SQLite date string to timestamp
            try:
                dt = datetime.strptime(date_modified_str, '%Y-%m-%d %H:%M:%S')
                mod_timestamp = dt.timestamp()
                modified_during_task = mod_timestamp > task_start
            except Exception as e:
                print(f'Date parse error: {e}')
                modified_during_task = False
            
            results['items'][key] = {
                'found': True,
                'item_id': item_id,
                'call_number': call_number,
                'modified_during_task': modified_during_task,
                'date_modified': date_modified_str
            }
        else:
            results['items'][key] = {
                'found': False
            }
            
    conn.close()
    
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
        
    print(f'Exported results to {output_file}')

except Exception as e:
    error_json = {'error': str(e)}
    with open(output_file, 'w') as f:
        json.dump(error_json, f)
    print(f'Error exporting: {e}')
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="
cat /tmp/task_result.json