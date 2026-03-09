#!/bin/bash
# Export script for embed_csl_variables task
echo "=== Exporting embed_csl_variables Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/csl_final.png
echo "Screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/embed_csl_variables_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# Python script to extract specific field values safely
python3 -c "
import sqlite3
import json
import os

db_path = '$JURISM_DB'
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'items_found': {},
    'error': None
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    targets = {
        'holmes': 'Path of the Law',
        'monaghan': 'Constitutional Fact Review',
        'poe': 'Due Process Clause'
    }

    for key, title_snippet in targets.items():
        # Find itemID by title (fieldID 1)
        c.execute('''
            SELECT items.itemID FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE fieldID=1 AND value LIKE ? LIMIT 1
        ''', (f'%{title_snippet}%',))
        
        row = c.fetchone()
        if row:
            item_id = row[0]
            # Get Extra field (fieldID 18)
            c.execute('''
                SELECT value FROM itemData 
                JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
                WHERE itemID=? AND fieldID=18 LIMIT 1
            ''', (item_id,))
            val_row = c.fetchone()
            extra_value = val_row[0] if val_row else ''
            
            result['items_found'][key] = {
                'found': True,
                'item_id': item_id,
                'extra_content': extra_value
            }
        else:
            result['items_found'][key] = {
                'found': False,
                'item_id': None,
                'extra_content': None
            }
            
    conn.close()

except Exception as e:
    result['error'] = str(e)

with open('/tmp/embed_csl_variables_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Set permissions
chmod 666 /tmp/embed_csl_variables_result.json 2>/dev/null || true
echo "Result saved to /tmp/embed_csl_variables_result.json"
cat /tmp/embed_csl_variables_result.json
echo "=== Export Complete ==="