#!/bin/bash
echo "=== Exporting catalog_historical_manuscript Result ==="
source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
JURISM_DB=$(get_jurism_db)

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism database not found"
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# We need to find the item ID of the newly created manuscript.
# Strategy: Look for an item of type 'manuscript' (typeName='manuscript') 
# created after TASK_START.

echo "Querying database for new manuscript..."

# 1. Get Item ID
ITEM_ID=$(sqlite3 "$JURISM_DB" "
SELECT items.itemID 
FROM items 
JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID 
WHERE itemTypes.typeName = 'manuscript' 
  AND items.dateAdded >= datetime($TASK_START, 'unixepoch')
ORDER BY items.dateAdded DESC 
LIMIT 1;
" 2>/dev/null)

FOUND="false"
TITLE=""
ARCHIVE=""
LOCATION=""
PLACE=""
MANUSCRIPT_TYPE=""
AUTHOR_LAST=""
AUTHOR_FIRST=""

if [ -n "$ITEM_ID" ] && [ "$ITEM_ID" != "0" ]; then
    FOUND="true"
    echo "Found new manuscript item ID: $ITEM_ID"

    # 2. Helper function to get field value by fieldName
    get_field_val() {
        local f_name="$1"
        sqlite3 "$JURISM_DB" "
        SELECT val.value 
        FROM itemData id
        JOIN fields f ON id.fieldID = f.fieldID
        JOIN itemDataValues val ON id.valueID = val.valueID
        WHERE id.itemID = $ITEM_ID AND f.fieldName = '$f_name';
        " 2>/dev/null
    }

    TITLE=$(get_field_val "title")
    ARCHIVE=$(get_field_val "repository")   # 'repository' is the internal field name for Archive
    if [ -z "$ARCHIVE" ]; then ARCHIVE=$(get_field_val "archive"); fi # Fallback if schema differs
    
    LOCATION=$(get_field_val "archiveLocation") # 'archiveLocation' corresponds to Loc. in Archive
    PLACE=$(get_field_val "place")
    MANUSCRIPT_TYPE=$(get_field_val "type")     # 'type' field for Manuscript Type
    
    # Get Author
    AUTHOR_DATA=$(sqlite3 "$JURISM_DB" "
    SELECT c.lastName, c.firstName 
    FROM itemCreators ic
    JOIN creators c ON ic.creatorID = c.creatorID
    JOIN creatorTypes ct ON ic.creatorTypeID = ct.creatorTypeID
    WHERE ic.itemID = $ITEM_ID AND ct.creatorType = 'author'
    ORDER BY ic.orderIndex ASC LIMIT 1;
    " 2>/dev/null)
    
    AUTHOR_LAST=$(echo "$AUTHOR_DATA" | awk -F'|' '{print $1}')
    AUTHOR_FIRST=$(echo "$AUTHOR_DATA" | awk -F'|' '{print $2}')
    
    echo "Extracted Data:"
    echo "Title: $TITLE"
    echo "Archive: $ARCHIVE"
    echo "Loc: $LOCATION"
    echo "Author: $AUTHOR_FIRST $AUTHOR_LAST"
else
    echo "No new manuscript item found."
fi

# JSON Export
# Use python to safely escape strings for JSON
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'item_found': $FOUND == 1,
    'item_id': '$ITEM_ID',
    'title': '''$TITLE''',
    'archive': '''$ARCHIVE''',
    'location': '''$LOCATION''',
    'place': '''$PLACE''',
    'manuscript_type': '''$MANUSCRIPT_TYPE''',
    'author_last': '''$AUTHOR_LAST''',
    'author_first': '''$AUTHOR_FIRST''',
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="