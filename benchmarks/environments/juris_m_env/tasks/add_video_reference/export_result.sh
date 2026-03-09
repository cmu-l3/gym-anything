#!/bin/bash
echo "=== Exporting add_video_reference results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get DB path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    # Create empty result
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# We need to find the item ID for "Hot Coffee"
# fieldID 1 is usually Title.
ITEM_ID=$(sqlite3 "$DB_PATH" "
SELECT items.itemID 
FROM items 
JOIN itemData ON items.itemID = itemData.itemID 
JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
WHERE items.itemTypeID NOT IN (1,3,31) 
AND itemData.fieldID = 1 
AND LOWER(itemDataValues.value) = 'hot coffee' 
LIMIT 1" 2>/dev/null || echo "")

ITEM_FOUND="false"
ITEM_TYPE=""
TITLE=""
DATE_VAL=""
RUNTIME=""
DISTRIBUTOR=""
CREATOR_LAST=""
CREATOR_ROLE=""
DATE_ADDED=""

if [ -n "$ITEM_ID" ]; then
    ITEM_FOUND="true"
    
    # Get Item Type Name
    ITEM_TYPE=$(sqlite3 "$DB_PATH" "SELECT typeName FROM itemTypes JOIN items ON itemTypes.itemTypeID = items.itemTypeID WHERE items.itemID = $ITEM_ID" 2>/dev/null || echo "")

    # Get Date Added
    DATE_ADDED=$(sqlite3 "$DB_PATH" "SELECT dateAdded FROM items WHERE itemID = $ITEM_ID" 2>/dev/null || echo "")

    # Get Metadata Fields via Field Names (more robust than hardcoded IDs)
    TITLE=$(sqlite3 "$DB_PATH" "SELECT value FROM itemDataValues JOIN itemData ON itemDataValues.valueID = itemData.valueID JOIN fields ON itemData.fieldID = fields.fieldID WHERE itemData.itemID = $ITEM_ID AND fields.fieldName = 'title'" 2>/dev/null || echo "")
    
    DATE_VAL=$(sqlite3 "$DB_PATH" "SELECT value FROM itemDataValues JOIN itemData ON itemDataValues.valueID = itemData.valueID JOIN fields ON itemData.fieldID = fields.fieldID WHERE itemData.itemID = $ITEM_ID AND fields.fieldName = 'date'" 2>/dev/null || echo "")
    
    RUNTIME=$(sqlite3 "$DB_PATH" "SELECT value FROM itemDataValues JOIN itemData ON itemDataValues.valueID = itemData.valueID JOIN fields ON itemData.fieldID = fields.fieldID WHERE itemData.itemID = $ITEM_ID AND fields.fieldName = 'runningTime'" 2>/dev/null || echo "")
    
    DISTRIBUTOR=$(sqlite3 "$DB_PATH" "SELECT value FROM itemDataValues JOIN itemData ON itemDataValues.valueID = itemData.valueID JOIN fields ON itemData.fieldID = fields.fieldID WHERE itemData.itemID = $ITEM_ID AND fields.fieldName = 'distributor'" 2>/dev/null || echo "")

    # Get Creator (Director)
    # We look for Susan Saladoff and get her role
    CREATOR_INFO=$(sqlite3 "$DB_PATH" "
    SELECT creators.lastName, creatorTypes.creatorType 
    FROM creators 
    JOIN itemCreators ON creators.creatorID = itemCreators.creatorID 
    JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID 
    WHERE itemCreators.itemID = $ITEM_ID 
    AND creators.lastName = 'Saladoff' 
    LIMIT 1" 2>/dev/null || echo "")
    
    if [ -n "$CREATOR_INFO" ]; then
        CREATOR_LAST=$(echo "$CREATOR_INFO" | cut -d'|' -f1)
        CREATOR_ROLE=$(echo "$CREATOR_INFO" | cut -d'|' -f2)
    fi
fi

# Escape for JSON
TITLE_ESC=$(echo "$TITLE" | sed 's/"/\\"/g')
DISTRIBUTOR_ESC=$(echo "$DISTRIBUTOR" | sed 's/"/\\"/g')
CREATOR_LAST_ESC=$(echo "$CREATOR_LAST" | sed 's/"/\\"/g')
ITEM_TYPE_ESC=$(echo "$ITEM_TYPE" | sed 's/"/\\"/g')

# Create JSON result
# Use a temp file and move it to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "item_found": $ITEM_FOUND,
    "item_id": "${ITEM_ID:-}",
    "item_type": "$ITEM_TYPE_ESC",
    "title": "$TITLE_ESC",
    "date": "$DATE_VAL",
    "running_time": "$RUNTIME",
    "distributor": "$DISTRIBUTOR_ESC",
    "creator_last": "$CREATOR_LAST_ESC",
    "creator_role": "$CREATOR_ROLE",
    "date_added": "$DATE_ADDED",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json