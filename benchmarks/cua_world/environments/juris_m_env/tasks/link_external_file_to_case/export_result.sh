#!/bin/bash
echo "=== Exporting link_external_file_to_case Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/link_task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
JURISM_DB=$(get_jurism_db)

if [ -z "$JURISM_DB" ]; then
    echo '{"error": "Database not found"}' > /tmp/link_external_file_to_case_result.json
    exit 1
fi

# Query DB for attachments to Miranda v. Arizona
# We need to find the attachment item and check its linkMode and path
# linkMode: 0=Imported, 1=Imported URL, 2=Linked File, 3=Linked URL
python3 -c "
import sqlite3
import json
import os

db_path = '$JURISM_DB'
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'miranda_found': False,
    'attachment_found': False,
    'link_mode': -1,
    'file_path': '',
    'screenshot_path': '/tmp/link_task_final.png'
}

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # 1. Find Parent Item (Miranda)
    c.execute('''
        SELECT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE fieldID IN (1, 58) AND value LIKE \"%Miranda%Arizona%\"
        LIMIT 1
    ''')
    row = c.fetchone()
    
    if row:
        result['miranda_found'] = True
        parent_id = row[0]
        
        # 2. Find Attachment
        # Look for a child in itemAttachments with a path containing 'Miranda_Opinion'
        # or just the most recent attachment to this parent
        c.execute('''
            SELECT linkMode, path FROM itemAttachments 
            WHERE parentItemID = ? 
            ORDER BY itemID DESC LIMIT 1
        ''', (parent_id,))
        
        att_row = c.fetchone()
        if att_row:
            result['attachment_found'] = True
            result['link_mode'] = att_row[0]
            result['file_path'] = att_row[1] if att_row[1] else ''
            
    conn.close()
except Exception as e:
    result['error'] = str(e)

with open('/tmp/link_external_file_to_case_result.json', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 /tmp/link_external_file_to_case_result.json 2>/dev/null || true

echo "Result saved to /tmp/link_external_file_to_case_result.json"
cat /tmp/link_external_file_to_case_result.json
echo "=== Export Complete ==="