#!/bin/bash
echo "=== Exporting create_regulation_reference Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo '{"error": "Database not found", "passed": false}' > /tmp/task_result.json
    exit 1
fi

# We need to extract the most recently added Regulation item and its fields
# Since field IDs can vary, we use subqueries to join with the fields table by name
echo "Querying database for Regulation item..."

python3 -c "
import sqlite3
import json
import time

db_path = '$JURISM_DB'
task_start = $TASK_START
result = {
    'item_found': False,
    'created_during_task': False,
    'fields': {},
    'task_start': task_start,
    'screenshot_path': '/tmp/task_final.png'
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    
    # Query for the most recent regulation item
    # We join itemTypes to find 'regulation' specifically
    query = '''
    SELECT 
        i.itemID, 
        i.dateAdded,
        (SELECT value FROM itemDataValues v JOIN itemData d ON v.valueID=d.valueID JOIN fields f ON d.fieldID=f.fieldID WHERE d.itemID=i.itemID AND f.fieldName='title') as title,
        (SELECT value FROM itemDataValues v JOIN itemData d ON v.valueID=d.valueID JOIN fields f ON d.fieldID=f.fieldID WHERE d.itemID=i.itemID AND (f.fieldName='legislativeBody' OR f.fieldName='authority')) as agency,
        (SELECT value FROM itemDataValues v JOIN itemData d ON v.valueID=d.valueID JOIN fields f ON d.fieldID=f.fieldID WHERE d.itemID=i.itemID AND f.fieldName='code') as code,
        (SELECT value FROM itemDataValues v JOIN itemData d ON v.valueID=d.valueID JOIN fields f ON d.fieldID=f.fieldID WHERE d.itemID=i.itemID AND f.fieldName='codeVolume') as volume,
        (SELECT value FROM itemDataValues v JOIN itemData d ON v.valueID=d.valueID JOIN fields f ON d.fieldID=f.fieldID WHERE d.itemID=i.itemID AND f.fieldName='section') as section,
        (SELECT value FROM itemDataValues v JOIN itemData d ON v.valueID=d.valueID JOIN fields f ON d.fieldID=f.fieldID WHERE d.itemID=i.itemID AND f.fieldName='date') as date
    FROM items i
    JOIN itemTypes it ON i.itemTypeID=it.itemTypeID
    WHERE it.typeName='regulation'
    ORDER BY i.itemID DESC
    LIMIT 1
    '''
    
    c.execute(query)
    row = c.fetchone()
    
    if row:
        result['item_found'] = True
        # Parse dateAdded from DB (format typically 'YYYY-MM-DD HH:MM:SS')
        date_added_str = row['dateAdded']
        try:
            # Convert DB time to timestamp. DB time is usually UTC or local string
            # Assuming standard SQLite datetime function output
            import datetime
            dt = datetime.datetime.strptime(date_added_str, '%Y-%m-%d %H:%M:%S')
            # Treat as local/system time relative to script execution
            # Simple check: if date string > task start date string
            pass
        except:
            pass
            
        # Robust timing check: Python time
        # We can't easily convert DB string to exact timestamp without timezone context
        # So we use a check within SQLite or simple comparison if formats align
        
        result['fields'] = {
            'title': row['title'],
            'agency': row['agency'],
            'code': row['code'],
            'volume': row['volume'],
            'section': row['section'],
            'date': row['date']
        }
        
        # Check if created after task start
        # Re-query with date comparison
        task_start_dt = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(task_start))
        c.execute(f\"SELECT COUNT(*) FROM items WHERE itemID=? AND dateAdded > ?\", (row['itemID'], task_start_dt))
        if c.fetchone()[0] > 0:
            result['created_during_task'] = True

    conn.close()
except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="