#!/bin/bash
echo "=== Exporting add_item_by_identifier result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_item_count.txt 2>/dev/null || echo "0")

# 1. Check Output File
OUTPUT_FILE="/home/ga/Documents/identifier_import_result.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | head -n 5) # Read first few lines
fi

# 2. Check Database for the Item
JURISM_DB=$(get_jurism_db)
ITEM_FOUND="false"
ITEM_DETAILS="{}"
CURRENT_COUNT=0

if [ -n "$JURISM_DB" ]; then
    CURRENT_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")

    # Python script to query DB robustly and return JSON
    ITEM_DETAILS=$(python3 -c "
import sqlite3
import json
import sys

try:
    conn = sqlite3.connect('$JURISM_DB')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    
    # Query for the item: Look for Book (type 7) with title containing 'Theory of Justice'
    # Jurism 6 Schema: itemTypeID 7 = book, fieldID 1 = title
    query = '''
        SELECT i.itemID, i.dateAdded, idv_title.value as title
        FROM items i
        JOIN itemData id_title ON i.itemID = id_title.itemID AND id_title.fieldID = 1
        JOIN itemDataValues idv_title ON id_title.valueID = idv_title.valueID
        WHERE i.itemTypeID = 7
          AND idv_title.value LIKE '%Theory of Justice%'
        ORDER BY i.dateAdded DESC
        LIMIT 1
    '''
    c.execute(query)
    row = c.fetchone()
    
    result = {'found': False}
    
    if row:
        result['found'] = True
        result['itemID'] = row['itemID']
        result['title'] = row['title']
        result['dateAdded'] = row['dateAdded']
        
        # Get Author (Creator)
        c.execute('''
            SELECT c.firstName, c.lastName 
            FROM itemCreators ic
            JOIN creators c ON ic.creatorID = c.creatorID
            WHERE ic.itemID = ? AND ic.creatorTypeID = 1
        ''', (row['itemID'],))
        creators = c.fetchall()
        result['creators'] = [{'firstName': cr['firstName'], 'lastName': cr['lastName']} for cr in creators]
        
        # Get Publisher (fieldID 20 usually, or via itemData)
        # We'll just dump all fields to be safe
        c.execute('''
            SELECT f.fieldName, idv.value
            FROM itemData id
            JOIN fields f ON id.fieldID = f.fieldID
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            WHERE id.itemID = ?
        ''', (row['itemID'],))
        fields = {r['fieldName']: r['value'] for r in c.fetchall()}
        result['fields'] = fields

    print(json.dumps(result))
    conn.close()

except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "file_verification": {
        "exists": $FILE_EXISTS,
        "content_preview": "$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ')"
    },
    "db_verification": $ITEM_DETAILS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json