#!/bin/bash
echo "=== Exporting configure_case_short_titles results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Create empty error result
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# Export data using Python for reliable JSON formatting and DB querying
python3 -c "
import sqlite3
import json
import os
import datetime

db_path = '$JURISM_DB'
task_start_ts = $TASK_START
output_path = '/tmp/task_result.json'

targets = [
    {'name': 'Brown v. Board of Education', 'expected': 'Brown'},
    {'name': 'Miranda v. Arizona', 'expected': 'Miranda'},
    {'name': 'Obergefell v. Hodges', 'expected': 'Obergefell'}
]

results = {
    'task_start': task_start_ts,
    'task_end': $TASK_END,
    'cases_data': []
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    for target in targets:
        case_name = target['name']
        
        # 1. Find itemID by caseName (fieldID=58)
        cursor.execute('''
            SELECT items.itemID, items.dateModified
            FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE fieldID=58 AND value LIKE ?
            ORDER BY items.dateModified DESC LIMIT 1
        ''', (f'%{case_name}%',))
        
        row = cursor.fetchone()
        
        case_result = {
            'target_name': case_name,
            'expected_short': target['expected'],
            'found': False,
            'item_id': None,
            'actual_short': None,
            'date_modified': None,
            'modified_during_task': False
        }
        
        if row:
            item_id, date_modified_str = row
            case_result['found'] = True
            case_result['item_id'] = item_id
            case_result['date_modified'] = date_modified_str
            
            # Check modification time
            # Format usually: YYYY-MM-DD HH:MM:SS
            try:
                mod_dt = datetime.datetime.strptime(date_modified_str, '%Y-%m-%d %H:%M:%S')
                mod_ts = mod_dt.timestamp()
                # Allow small buffer for clock skew
                if mod_ts >= (task_start_ts - 5):
                    case_result['modified_during_task'] = True
            except Exception as e:
                print(f'Date parse error: {e}')
            
            # 2. Get Short Title (fieldID=3)
            cursor.execute('''
                SELECT value 
                FROM itemData 
                JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
                WHERE itemID=? AND fieldID=3
            ''', (item_id,))
            
            st_row = cursor.fetchone()
            if st_row:
                case_result['actual_short'] = st_row[0]
            else:
                case_result['actual_short'] = '' # Empty or None
        
        results['cases_data'].append(case_result)

    conn.close()

except Exception as e:
    results['error'] = str(e)

with open(output_path, 'w') as f:
    json.dump(results, f, indent=4)

print(f'Exported {len(results["cases_data"])} case results to {output_path}')
"

# Handle permissions for copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json