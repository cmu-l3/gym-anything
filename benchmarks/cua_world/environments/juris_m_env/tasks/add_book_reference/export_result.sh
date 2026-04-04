#!/bin/bash
echo "=== Exporting add_book_reference Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_BOOK_COUNT=$(cat /tmp/initial_book_count.txt 2>/dev/null || echo "0")

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/task_result.json << EOF
{
    "error": "Jurism database not found",
    "db_exists": false,
    "timestamp": "$(date -Iseconds)"
}
EOF
    exit 0
fi

# Helper function to query DB securely
db_query() {
    sqlite3 "$JURISM_DB" "$1" 2>/dev/null || echo ""
}

# 1. Find the target item ID
# We look for a Book created after task start, or matching the title "Legal Process"
BOOK_TYPE_ID=$(db_query "SELECT itemTypeID FROM itemTypes WHERE typeName = 'book' LIMIT 1")
[ -z "$BOOK_TYPE_ID" ] && BOOK_TYPE_ID=7

if [ "$TASK_START" -gt 0 ]; then
    TASK_START_DT=$(date -d "@$TASK_START" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "1970-01-01 00:00:00")
else
    TASK_START_DT="1970-01-01 00:00:00"
fi

# Try finding by title first (most robust)
ITEM_ID=$(db_query "
    SELECT i.itemID FROM items i
    JOIN itemData id ON i.itemID = id.itemID
    JOIN itemDataValues idv ON id.valueID = idv.valueID
    JOIN fields f ON id.fieldID = f.fieldID
    WHERE i.itemTypeID = $BOOK_TYPE_ID 
    AND f.fieldName = 'title' 
    AND idv.value LIKE '%Legal Process%'
    ORDER BY i.dateAdded DESC LIMIT 1
")

# If not found by title, try finding newest book created during task
if [ -z "$ITEM_ID" ]; then
    ITEM_ID=$(db_query "
        SELECT itemID FROM items 
        WHERE itemTypeID = $BOOK_TYPE_ID 
        AND dateAdded > '$TASK_START_DT'
        ORDER BY dateAdded DESC LIMIT 1
    ")
fi

ITEM_FOUND="false"
CREATED_DURING_TASK="false"
TITLE=""
PUBLISHER=""
PLACE=""
DATE_VAL=""
NUM_PAGES=""
ISBN=""
CREATORS_JSON="[]"

if [ -n "$ITEM_ID" ]; then
    ITEM_FOUND="true"
    
    # Check creation time
    ITEM_DATE_ADDED=$(db_query "SELECT dateAdded FROM items WHERE itemID = $ITEM_ID")
    # Simple string comparison for SQL timestamps YYYY-MM-DD HH:MM:SS
    if [[ "$ITEM_DATE_ADDED" > "$TASK_START_DT" ]]; then
        CREATED_DURING_TASK="true"
    fi

    # Extract fields using field names
    get_field_val() {
        local fname="$1"
        db_query "
            SELECT idv.value FROM itemData id
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            JOIN fields f ON id.fieldID = f.fieldID
            WHERE id.itemID = $ITEM_ID AND f.fieldName = '$fname'
        "
    }

    TITLE=$(get_field_val "title")
    PUBLISHER=$(get_field_val "publisher")
    PLACE=$(get_field_val "place")
    DATE_VAL=$(get_field_val "date")
    NUM_PAGES=$(get_field_val "numPages")
    ISBN=$(get_field_val "ISBN")

    # Extract creators
    # Format: [{"first": "X", "last": "Y"}, ...]
    CREATORS_RAW=$(db_query "
        SELECT c.firstName, c.lastName FROM itemCreators ic
        JOIN creators c ON ic.creatorID = c.creatorID
        WHERE ic.itemID = $ITEM_ID
        ORDER BY ic.orderIndex
    ")
    
    # Convert pipe-separated SQL output to JSON array using python
    CREATORS_JSON=$(python3 -c "
import sys, json
raw = '''$CREATORS_RAW'''
creators = []
for line in raw.strip().split('\n'):
    if '|' in line:
        first, last = line.split('|', 1)
        creators.append({'first': first.strip(), 'last': last.strip()})
print(json.dumps(creators))
")
fi

# Get total book count
CURRENT_BOOK_COUNT=$(db_query "SELECT COUNT(*) FROM items WHERE itemTypeID = $BOOK_TYPE_ID")

# Escape fields for JSON
escape_json() {
    echo "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

TITLE_JSON=$(escape_json "$TITLE")
PUB_JSON=$(escape_json "$PUBLISHER")
PLACE_JSON=$(escape_json "$PLACE")
DATE_JSON=$(escape_json "$DATE_VAL")
PAGES_JSON=$(escape_json "$NUM_PAGES")
ISBN_JSON=$(escape_json "$ISBN")

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_exists": true,
    "initial_book_count": $INITIAL_BOOK_COUNT,
    "current_book_count": $CURRENT_BOOK_COUNT,
    "item_found": $ITEM_FOUND,
    "created_during_task": $CREATED_DURING_TASK,
    "item": {
        "id": "${ITEM_ID:-}",
        "title": $TITLE_JSON,
        "publisher": $PUB_JSON,
        "place": $PLACE_JSON,
        "date": $DATE_JSON,
        "num_pages": $PAGES_JSON,
        "isbn": $ISBN_JSON,
        "creators": $CREATORS_JSON
    },
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="