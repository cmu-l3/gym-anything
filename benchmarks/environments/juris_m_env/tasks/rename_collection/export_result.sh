#!/bin/bash
echo "=== Exporting rename_collection result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Load initial state
INITIAL_COLL_ID=$(cat /tmp/initial_collection_id.txt 2>/dev/null || echo "")
INITIAL_ITEM_COUNT=$(cat /tmp/initial_item_count.txt 2>/dev/null || echo "0")

# Get DB path
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Create error JSON
    cat > /tmp/task_result.json <<EOF
{
    "error": "Database not found",
    "passed": false
}
EOF
    exit 1
fi

# 1. Check if "Research" still exists
OLD_NAME_EXISTS=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM collections WHERE collectionName='Research';" 2>/dev/null || echo "0")

# 2. Check if "First Amendment Jurisprudence" exists
NEW_NAME_EXISTS=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM collections WHERE collectionName='First Amendment Jurisprudence';" 2>/dev/null || echo "0")

# 3. Get details of the new collection (if it exists)
NEW_COLL_ID=""
NEW_COLL_ITEM_COUNT="0"
NEW_COLL_KEY=""

if [ "$NEW_NAME_EXISTS" -gt 0 ]; then
    # Get ID
    NEW_COLL_ID=$(sqlite3 "$JURISM_DB" "SELECT collectionID FROM collections WHERE collectionName='First Amendment Jurisprudence' LIMIT 1;" 2>/dev/null || echo "")
    # Get Key
    NEW_COLL_KEY=$(sqlite3 "$JURISM_DB" "SELECT key FROM collections WHERE collectionName='First Amendment Jurisprudence' LIMIT 1;" 2>/dev/null || echo "")
    # Get Item Count
    if [ -n "$NEW_COLL_ID" ]; then
        NEW_COLL_ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM collectionItems WHERE collectionID=$NEW_COLL_ID;" 2>/dev/null || echo "0")
    fi
fi

# 4. Check timestamps (anti-gaming)
# Check if the collection was modified after task start
MODIFIED_DURING_TASK="false"
if [ -n "$NEW_COLL_ID" ]; then
    # Convert SQLite text date to seconds
    COLL_MOD_TIME=$(sqlite3 "$JURISM_DB" "SELECT strftime('%s', dateModified) FROM collections WHERE collectionID=$NEW_COLL_ID;" 2>/dev/null || echo "0")
    
    # Allow a small buffer for clock skew, but strictly > task start is safer
    if [ "$COLL_MOD_TIME" -ge "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
    echo "Collection mod time: $COLL_MOD_TIME, Task start: $TASK_START"
fi

# Prepare JSON result
# Use python for safer JSON generation
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_collection_id': '${INITIAL_COLL_ID:-}',
    'initial_item_count': ${INITIAL_ITEM_COUNT:-0},
    'old_name_exists': True if $OLD_NAME_EXISTS > 0 else False,
    'new_name_exists': True if $NEW_NAME_EXISTS > 0 else False,
    'new_collection_id': '${NEW_COLL_ID:-}',
    'new_collection_key': '${NEW_COLL_KEY:-}',
    'new_collection_item_count': ${NEW_COLL_ITEM_COUNT:-0},
    'modified_during_task': True if '$MODIFIED_DURING_TASK' == 'true' else False,
    'screenshot_path': '/tmp/task_final_state.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="