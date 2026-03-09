#!/bin/bash
echo "=== Exporting add_hearing_reference Result ==="
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_hearing_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Database not found"
    cat > /tmp/task_result.json << EOF
{"error": "Database not found", "passed": false}
EOF
    exit 1
fi

# Export data using Python for robust SQLite handling
python3 -c "
import sqlite3
import json
import os
import sys

db_path = '$JURISM_DB'
task_start = $TASK_START
initial_count = $INITIAL_COUNT
result = {
    'task_start': task_start,
    'task_end': $TASK_END,
    'initial_hearing_count': initial_count,
    'final_hearing_count': 0,
    'item_found': False,
    'item_details': {},
    'created_during_task': False,
    'screenshot_path': '/tmp/task_final.png'
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Get final count of hearings
    c.execute(\"SELECT COUNT(*) FROM items JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID WHERE typeName = 'hearing'\")
    result['final_hearing_count'] = c.fetchone()[0]

    # Find the specific item: Look for 'Watergate' in title AND type='hearing'
    # We prioritize items created after task start
    
    query = '''
        SELECT items.itemID, items.dateAdded
        FROM items 
        JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        JOIN fields ON itemData.fieldID = fields.fieldID
        WHERE items.itemTypeID NOT IN (1, 3, 31) -- Exclude attachments/notes
          AND itemTypes.typeName = 'hearing'
          AND fields.fieldName = 'title'
          AND itemDataValues.value LIKE '%Watergate%'
        ORDER BY items.dateAdded DESC
        LIMIT 1
    '''
    
    c.execute(query)
    row = c.fetchone()
    
    if row:
        result['item_found'] = True
        item_id = row['itemID']
        date_added = row['dateAdded'] # String format usually
        
        # Check if created during task (simple string comparison works for ISO dates if format is consistent)
        # Or we can rely on verifier to parse.
        # Ideally we convert task_start to SQL format or just pass the raw dateAdded string.
        result['item_details']['dateAdded'] = date_added
        
        # Fetch all fields for this item
        field_query = '''
            SELECT fields.fieldName, itemDataValues.value
            FROM itemData
            JOIN fields ON itemData.fieldID = fields.fieldID
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            WHERE itemData.itemID = ?
        '''
        c.execute(field_query, (item_id,))
        fields = {}
        for field_row in c.fetchall():
            fields[field_row['fieldName']] = field_row['value']
            
        result['item_details']['fields'] = fields
        
        # Determine if new based on count or specific timestamp check logic in verifier
        # But we can flag it here if we see it in the DB
        result['item_id'] = item_id

    conn.close()
    
except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="