#!/bin/bash
echo "=== Exporting add_software_reference Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/software_task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/add_software_reference_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# We use Python to query the DB complexly and export structured JSON
python3 -c "
import sqlite3
import json
import os
import sys

db_path = '$JURISM_DB'
task_start = $TASK_START
result = {
    'task_start': task_start,
    'item_found': False,
    'item_type_correct': False,
    'metadata': {},
    'creator': {}
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Find the item by title
    # FieldID 1 is Title
    c.execute('''
        SELECT items.itemID, items.itemTypeID, items.dateAdded 
        FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE itemData.fieldID = 1 AND itemDataValues.value LIKE 'R: A Language%'
        ORDER BY items.dateAdded DESC LIMIT 1
    ''')
    row = c.fetchone()
    
    if row:
        result['item_found'] = True
        item_id = row['itemID']
        type_id = row['itemTypeID']
        
        # Check item type name
        c.execute('SELECT typeName FROM itemTypes WHERE itemTypeID = ?', (type_id,))
        type_row = c.fetchone()
        type_name = type_row['typeName'] if type_row else str(type_id)
        result['item_type'] = type_name
        
        # Check if type is computerProgram (usually ID 27, but relying on name is safer if possible)
        # Zotero standard: computerProgram. Jurism might vary slightly but usually same.
        if type_name == 'computerProgram':
            result['item_type_correct'] = True

        # 2. Get Metadata Fields
        # Common Field IDs:
        # 1: Title
        # 6: Date (or 8)
        # 10: Version
        # 11: Place
        # 13: Company (Publisher)
        # 15: URL
        
        field_map = {
            1: 'title',
            6: 'date', 
            8: 'date',
            10: 'version',
            11: 'place',
            13: 'company',
            15: 'url'
        }
        
        c.execute('''
            SELECT fieldID, value 
            FROM itemData 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE itemID = ?
        ''', (item_id,))
        
        for field_row in c.fetchall():
            fid = field_row['fieldID']
            val = field_row['value']
            if fid in field_map:
                key = field_map[fid]
                # If key exists (e.g. date can be 6 or 8), don't overwrite if we have a value
                if key not in result['metadata']:
                    result['metadata'][key] = val

        # 3. Get Creator Info
        # We are looking for 'R Core Team'.
        c.execute('''
            SELECT creators.firstName, creators.lastName, creators.fieldMode, itemCreators.creatorTypeID
            FROM itemCreators
            JOIN creators ON itemCreators.creatorID = creators.creatorID
            WHERE itemCreators.itemID = ?
            ORDER BY itemCreators.orderIndex ASC
        ''', (item_id,))
        
        creators = c.fetchall()
        # Look for the relevant creator
        for creat in creators:
            # We want the one that looks like R Core Team
            lname = creat['lastName']
            fname = creat['firstName']
            mode = creat['fieldMode']
            
            # Capture data for verifier
            # If mode=1 (single field), lastName holds the full name
            full_name = lname
            if mode == 0 and fname:
                full_name = f'{lname}, {fname}'
            
            # Store the first creator found, or specifically R Core Team if multiple
            if 'R Core Team' in full_name or 'R Core' in full_name or 'Team' in full_name:
                result['creator'] = {
                    'lastName': lname,
                    'firstName': fname,
                    'fieldMode': mode,
                    'full_string': full_name
                }
                break
        
        # If no specific match, just take the first one
        if not result['creator'] and creators:
            creat = creators[0]
            result['creator'] = {
                'lastName': creat['lastName'],
                'firstName': creat['firstName'],
                'fieldMode': creat['fieldMode'],
                'full_string': creat['lastName'] + (f', {creat[\'firstName\']}' if creat['fieldMode'] == 0 else '')
            }

    conn.close()
except Exception as e:
    result['error'] = str(e)

# Write result
with open('/tmp/add_software_reference_result.json', 'w') as f:
    json.dump(result, f)
"

# Permissions
chmod 666 /tmp/add_software_reference_result.json 2>/dev/null || true
echo "Result saved to /tmp/add_software_reference_result.json"
cat /tmp/add_software_reference_result.json
echo "=== Export Complete ==="