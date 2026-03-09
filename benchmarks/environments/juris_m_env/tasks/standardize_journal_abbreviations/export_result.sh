#!/bin/bash
echo "=== Exporting standardize_journal_abbreviations Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/abbr_final.png
echo "Screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/standardize_journal_abbreviations_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# We use Python to query the DB and build the result JSON safely
# This handles the complexity of joining multiple tables (items, itemData, fields, itemDataValues)
python3 -c "
import sqlite3
import json
import time

db_path = '$JURISM_DB'
task_start = int('$TASK_START')
task_end = int('$TASK_END')

targets = [
    'The Path of the Law',
    'Constitutional Fact Review',
    'The Due Process Clause and the Substantive Law of Torts'
]

results = {
    'task_start': task_start,
    'task_end': task_end,
    'screenshot_path': '/tmp/abbr_final.png',
    'items': {}
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Get fieldID for 'journalAbbreviation'
    c.execute(\"SELECT fieldID FROM fields WHERE fieldName='journalAbbreviation'\")
    row = c.fetchone()
    abbr_field_id = row[0] if row else 12  # Default to 12 if not found, though verification relies on field name mapping logic usually
    
    for title in targets:
        item_res = {
            'found': False,
            'abbr_value': None,
            'modified_time': 0,
            'modified_during_task': False
        }
        
        # 1. Find Item ID by Title
        # Note: fieldID 1 is usually 'title'
        c.execute('''
            SELECT items.itemID, items.dateModified 
            FROM items
            JOIN itemData ON items.itemID = itemData.itemID
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            JOIN fields ON itemData.fieldID = fields.fieldID
            WHERE fields.fieldName='title' AND itemDataValues.value=?
        ''', (title,))
        
        item_row = c.fetchone()
        
        if item_row:
            item_res['found'] = True
            iid = item_row[0]
            date_mod_str = item_row[1] # format usually 'YYYY-MM-DD HH:MM:SS'
            
            # Parse modification time
            try:
                # Convert UTC string to timestamp
                # SQLite dates are strings. We need to be careful with timezone.
                # Assuming simple comparison or string parsing.
                # Let's just store the string for the verifier, and checks relative order if possible
                pass 
            except:
                pass
                
            # Check for modification during task using SQL date comparison
            # We compare the string directly which works for ISO format
            task_start_dt = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(task_start))
            if date_mod_str > task_start_dt:
                item_res['modified_during_task'] = True
            
            item_res['modified_time_str'] = date_mod_str

            # 2. Get Journal Abbreviation Value
            c.execute('''
                SELECT value 
                FROM itemData 
                JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
                WHERE itemID=? AND fieldID=?
            ''', (iid, abbr_field_id))
            
            abbr_row = c.fetchone()
            if abbr_row:
                item_res['abbr_value'] = abbr_row[0]
        
        results['items'][title] = item_res

    conn.close()

except Exception as e:
    results['error'] = str(e)

# Write output
with open('/tmp/standardize_journal_abbreviations_result.json', 'w') as f:
    json.dump(results, f, indent=2)
"

chmod 666 /tmp/standardize_journal_abbreviations_result.json 2>/dev/null || true
echo "Result saved to /tmp/standardize_journal_abbreviations_result.json"
cat /tmp/standardize_journal_abbreviations_result.json
echo "=== Export Complete ==="