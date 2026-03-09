#!/bin/bash
echo "=== Exporting add_cle_presentation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Locate database
DB_PATH=$(get_jurism_db)

if [ -z "$DB_PATH" ]; then
    echo "ERROR: Database not found"
    cat > /tmp/task_result.json << EOF
{
    "error": "Database not found",
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF
    exit 0
fi

# Query to find the target item
# We look for an item with the specific title
TARGET_TITLE="The Future of Legal Tech: AI and Ethics"

# 1. Get Item ID
ITEM_ID=$(sqlite3 "$DB_PATH" "SELECT DISTINCT itemData.itemID FROM itemData JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID JOIN fields ON itemData.fieldID = fields.fieldID WHERE fields.fieldName = 'title' AND itemDataValues.value = '$TARGET_TITLE' LIMIT 1;" 2>/dev/null)

ITEM_FOUND="false"
ITEM_TYPE=""
DATE_ADDED=""
CREATORS_JSON="[]"
FIELDS_JSON="{}"

if [ -n "$ITEM_ID" ]; then
    ITEM_FOUND="true"
    
    # 2. Get Item Type and Date Added
    ITEM_INFO=$(sqlite3 "$DB_PATH" "SELECT typeName, dateAdded FROM items JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID WHERE items.itemID = $ITEM_ID;" 2>/dev/null)
    ITEM_TYPE=$(echo "$ITEM_INFO" | cut -d'|' -f1)
    DATE_ADDED=$(echo "$ITEM_INFO" | cut -d'|' -f2)
    
    # 3. Get Metadata Fields
    # Construct a JSON object of field_name: value
    # We use python to handle JSON construction safely to avoid escaping hell in bash
    FIELDS_JSON=$(python3 << PY_SCRIPT
import sqlite3
import json

conn = sqlite3.connect('$DB_PATH')
c = conn.cursor()
c.execute("""
    SELECT fields.fieldName, itemDataValues.value 
    FROM itemData 
    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
    JOIN fields ON itemData.fieldID = fields.fieldID 
    WHERE itemData.itemID = $ITEM_ID
""")
fields = dict(c.fetchall())
print(json.dumps(fields))
PY_SCRIPT
)

    # 4. Get Creators
    # Construct a JSON list of {first, last, type}
    CREATORS_JSON=$(python3 << PY_SCRIPT
import sqlite3
import json

conn = sqlite3.connect('$DB_PATH')
c = conn.cursor()
c.execute("""
    SELECT creators.firstName, creators.lastName, creatorTypes.creatorType 
    FROM itemCreators 
    JOIN creators ON itemCreators.creatorID = creators.creatorID 
    JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID 
    WHERE itemCreators.itemID = $ITEM_ID 
    ORDER BY itemCreators.orderIndex
""")
creators = [{"firstName": r[0], "lastName": r[1], "type": r[2]} for r in c.fetchall()]
print(json.dumps(creators))
PY_SCRIPT
)

fi

# Construct final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "item_found": $ITEM_FOUND,
    "item_id": "${ITEM_ID:-0}",
    "item_type": "$ITEM_TYPE",
    "item_date_added": "$DATE_ADDED",
    "fields": $FIELDS_JSON,
    "creators": $CREATORS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="