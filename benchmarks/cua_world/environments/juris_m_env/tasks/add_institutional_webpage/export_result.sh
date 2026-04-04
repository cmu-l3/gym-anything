#!/bin/bash
echo "=== Exporting add_institutional_webpage Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/task_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# We need to find the item ID for "2023 Merger Guidelines"
# fieldID 1 = Title
ITEM_ID=$(sqlite3 "$JURISM_DB" "
SELECT items.itemID FROM items
JOIN itemData ON items.itemID = itemData.itemID
JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
WHERE fieldID=1 AND value = '2023 Merger Guidelines'
ORDER BY items.itemID DESC LIMIT 1
" 2>/dev/null || echo "")

ITEM_FOUND="false"
ITEM_TYPE_ID=""
AUTHOR_LASTNAME=""
AUTHOR_FIELDMODE=""
WEBSITE_TITLE=""
DATE_VAL=""
URL_VAL=""
CREATED_DURING_TASK="false"

if [ -n "$ITEM_ID" ]; then
    ITEM_FOUND="true"
    
    # Check creation time
    TASK_START_DT=$(date -d "@$TASK_START" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "1970-01-01 00:00:00")
    ADDED_AFTER=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemID=$ITEM_ID AND dateAdded > '$TASK_START_DT'" 2>/dev/null || echo "0")
    [ "$ADDED_AFTER" -gt 0 ] && CREATED_DURING_TASK="true"

    # Get Item Type
    ITEM_TYPE_ID=$(sqlite3 "$JURISM_DB" "SELECT itemTypeID FROM items WHERE itemID=$ITEM_ID" 2>/dev/null || echo "")

    # Get Creator Info (Author)
    # We look for the creator linked to this item.
    # We assume it's the first creator.
    CREATOR_ID=$(sqlite3 "$JURISM_DB" "SELECT creatorID FROM itemCreators WHERE itemID=$ITEM_ID ORDER BY orderIndex ASC LIMIT 1" 2>/dev/null || echo "")
    
    if [ -n "$CREATOR_ID" ]; then
        AUTHOR_LASTNAME=$(sqlite3 "$JURISM_DB" "SELECT lastName FROM creators WHERE creatorID=$CREATOR_ID" 2>/dev/null || echo "")
        AUTHOR_FIELDMODE=$(sqlite3 "$JURISM_DB" "SELECT fieldMode FROM creators WHERE creatorID=$CREATOR_ID" 2>/dev/null || echo "")
    fi

    # Get Metadata Fields
    # Website Title (Publication Title) is typically fieldID 7
    WEBSITE_TITLE=$(sqlite3 "$JURISM_DB" "
        SELECT value FROM itemData 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE itemID=$ITEM_ID AND fieldID=7 LIMIT 1
    " 2>/dev/null || echo "")

    # Date is fieldID 8
    DATE_VAL=$(sqlite3 "$JURISM_DB" "
        SELECT value FROM itemData 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE itemID=$ITEM_ID AND fieldID=8 LIMIT 1
    " 2>/dev/null || echo "")

    # URL is fieldID 13
    URL_VAL=$(sqlite3 "$JURISM_DB" "
        SELECT value FROM itemData 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE itemID=$ITEM_ID AND fieldID=13 LIMIT 1
    " 2>/dev/null || echo "")

fi

# JSON Export
# Escape strings
AUTHOR_LASTNAME_ESC=$(echo "$AUTHOR_LASTNAME" | sed 's/"/\\"/g')
WEBSITE_TITLE_ESC=$(echo "$WEBSITE_TITLE" | sed 's/"/\\"/g')
URL_VAL_ESC=$(echo "$URL_VAL" | sed 's/"/\\"/g')
DATE_VAL_ESC=$(echo "$DATE_VAL" | sed 's/"/\\"/g')

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "item_found": $ITEM_FOUND,
    "item_id": "${ITEM_ID}",
    "created_during_task": $CREATED_DURING_TASK,
    "item_type_id": "${ITEM_TYPE_ID}",
    "author_name": "${AUTHOR_LASTNAME_ESC}",
    "author_field_mode": "${AUTHOR_FIELDMODE}",
    "website_title": "${WEBSITE_TITLE_ESC}",
    "date": "${DATE_VAL_ESC}",
    "url": "${URL_VAL_ESC}",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="