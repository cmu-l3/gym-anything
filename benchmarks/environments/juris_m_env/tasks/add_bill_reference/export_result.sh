#!/bin/bash
echo "=== Exporting task results: add_bill_reference ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
take_screenshot /tmp/task_final_state.png

DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    # Create empty result to avoid verifier crash
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# Read setup data
TASK_START=$(cat /tmp/task_start_time_formatted.txt 2>/dev/null || echo "2000-01-01 00:00:00")
INITIAL_BILL_COUNT=$(cat /tmp/initial_bill_count.txt 2>/dev/null || echo "0")
INITIAL_ITEM_COUNT=$(cat /tmp/initial_item_count.txt 2>/dev/null || echo "0")

# 1. Identify Bill Item Type ID
BILL_TYPE_ID=$(sqlite3 -readonly "$DB_PATH" "SELECT itemTypeID FROM itemTypes WHERE typeName = 'bill'" 2>/dev/null || echo "")
if [ -z "$BILL_TYPE_ID" ]; then
    # Fallback lookup
    BILL_TYPE_ID=$(sqlite3 -readonly "$DB_PATH" "SELECT itemTypeID FROM itemTypes WHERE LOWER(typeName) LIKE '%bill%'" 2>/dev/null | head -1 || echo "")
fi

# 2. Find new bill items added after start time
# Query returns itemID of the most recently added bill
NEW_BILL_ID=""
if [ -n "$BILL_TYPE_ID" ]; then
    NEW_BILL_ID=$(sqlite3 -readonly "$DB_PATH" "SELECT i.itemID FROM items i WHERE i.itemTypeID = $BILL_TYPE_ID AND i.dateAdded >= '$TASK_START' ORDER BY i.dateAdded DESC LIMIT 1" 2>/dev/null || echo "")
fi

# If no new bill found by timestamp, check if bill count increased and pick the latest one (fallback)
CURRENT_BILL_COUNT=$(sqlite3 -readonly "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID = ${BILL_TYPE_ID:-0}" 2>/dev/null || echo "0")
if [ -z "$NEW_BILL_ID" ] && [ "$CURRENT_BILL_COUNT" -gt "$INITIAL_BILL_COUNT" ]; then
    NEW_BILL_ID=$(sqlite3 -readonly "$DB_PATH" "SELECT i.itemID FROM items i WHERE i.itemTypeID = $BILL_TYPE_ID ORDER BY i.dateAdded DESC LIMIT 1" 2>/dev/null || echo "")
fi

# 3. Extract Metadata for the found bill
BILL_FOUND="false"
TITLE=""
BILL_NUM=""
LEGIS_BODY=""
SESSION=""
DATE=""
ABSTRACT=""
CREATOR_LAST=""
CREATOR_FIRST=""
CREATOR_ROLE_ID=""

if [ -n "$NEW_BILL_ID" ]; then
    BILL_FOUND="true"
    
    # Helper to extract field value
    get_val() {
        local fname="$1"
        sqlite3 -readonly "$DB_PATH" "SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID = v.valueID JOIN fields f ON d.fieldID = f.fieldID WHERE d.itemID = $NEW_BILL_ID AND f.fieldName = '$fname'" 2>/dev/null || echo ""
    }

    TITLE=$(get_val "title")
    BILL_NUM=$(get_val "billNumber")
    LEGIS_BODY=$(get_val "legislativeBody")
    SESSION=$(get_val "session")
    DATE=$(get_val "date")
    ABSTRACT=$(get_val "abstractNote")

    # Get creator info
    CREATOR_INFO=$(sqlite3 -readonly "$DB_PATH" "SELECT c.lastName, c.firstName, ic.creatorTypeID FROM itemCreators ic JOIN creators c ON ic.creatorID = c.creatorID WHERE ic.itemID = $NEW_BILL_ID ORDER BY ic.orderIndex LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$CREATOR_INFO" ]; then
        CREATOR_LAST=$(echo "$CREATOR_INFO" | cut -d'|' -f1)
        CREATOR_FIRST=$(echo "$CREATOR_INFO" | cut -d'|' -f2)
        CREATOR_ROLE_ID=$(echo "$CREATOR_INFO" | cut -d'|' -f3)
    fi
fi

# 4. Prepare JSON result
# Use python to construct JSON to handle escaping safely
python3 -c "
import json
import sys

data = {
    'initial_bill_count': int('$INITIAL_BILL_COUNT'),
    'current_bill_count': int('$CURRENT_BILL_COUNT'),
    'bill_found': '$BILL_FOUND' == 'true',
    'bill_id': '$NEW_BILL_ID',
    'metadata': {
        'title': '''$TITLE''',
        'bill_number': '''$BILL_NUM''',
        'legislative_body': '''$LEGIS_BODY''',
        'session': '''$SESSION''',
        'date': '''$DATE''',
        'abstract': '''$ABSTRACT'''
    },
    'creator': {
        'last_name': '''$CREATOR_LAST''',
        'first_name': '''$CREATOR_FIRST''',
        'role_id': '$CREATOR_ROLE_ID'
    },
    'screenshot_path': '/tmp/task_final_state.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="