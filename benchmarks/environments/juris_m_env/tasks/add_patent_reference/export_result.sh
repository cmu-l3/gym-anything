#!/bin/bash
echo "=== Exporting add_patent_reference results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Database not found"
    cat > /tmp/add_patent_reference_result.json << EOF
{
    "error": "Database not found",
    "passed": false
}
EOF
    exit 1
fi

# Use Python to robustly query the SQLite DB and extract item details
# We look for the most recently added Patent item
python3 -c "
import sqlite3
import json
import os
import sys

db_path = '$JURISM_DB'
task_start = int($TASK_START)
result = {
    'task_start': task_start,
    'db_found': True,
    'patent_found': False,
    'item_details': {},
    'created_during_task': False
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # 1. Get Patent Type ID
    c.execute(\"SELECT itemTypeID FROM itemTypes WHERE typeName='patent'\")
    row = c.fetchone()
    if not row:
        # Fallback for some schemas
        patent_type_id = 19
    else:
        patent_type_id = row[0]
        
    # 2. Find patent items matching title fragment OR just the most recent patent
    # We prioritize matching the title
    c.execute('''
        SELECT items.itemID, items.dateAdded 
        FROM items 
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        WHERE items.itemTypeID = ? 
        AND itemDataValues.value LIKE '%unlocking a device%'
        ORDER BY items.dateAdded DESC LIMIT 1
    ''', (patent_type_id,))
    
    match = c.fetchone()
    
    if match:
        item_id = match[0]
        date_added = match[1] # format YYYY-MM-DD HH:MM:SS
        result['patent_found'] = True
        
        # Check timestamp (simple string comparison works for ISO dates vs task start if converted)
        # But here we rely on the verify logic or just check if it exists now
        
        # Extract fields
        fields = {}
        c.execute('''
            SELECT fields.fieldName, itemDataValues.value
            FROM itemData
            JOIN fields ON itemData.fieldID = fields.fieldID
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            WHERE itemData.itemID = ?
        ''', (item_id,))
        
        for f_name, f_val in c.fetchall():
            fields[f_name] = f_val
            
        result['item_details'] = fields
        
        # Extract Creators
        creators = []
        c.execute('''
            SELECT creators.firstName, creators.lastName, creatorTypes.creatorType
            FROM itemCreators
            JOIN creators ON itemCreators.creatorID = creators.creatorID
            JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
            WHERE itemCreators.itemID = ?
            ORDER BY itemCreators.orderIndex
        ''', (item_id,))
        
        for first, last, role in c.fetchall():
            creators.append({'first': first, 'last': last, 'role': role})
            
        result['creators'] = creators
        
        # Check if created after task start
        # Convert DB date string to unix
        import datetime
        try:
            # Jurism dateAdded is typically 'YYYY-MM-DD HH:MM:SS' in UTC or local
            dt = datetime.datetime.strptime(date_added, '%Y-%m-%d %H:%M:%S')
            created_ts = dt.timestamp()
            # Allow small clock skew (e.g. 60s)
            if created_ts >= (task_start - 60):
                result['created_during_task'] = True
        except:
            pass # Keep false if parsing fails

    conn.close()

except Exception as e:
    result['error'] = str(e)

with open('/tmp/add_patent_reference_result.json', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 /tmp/add_patent_reference_result.json 2>/dev/null || true
echo "Result exported to /tmp/add_patent_reference_result.json"
cat /tmp/add_patent_reference_result.json
echo "=== Export complete ==="