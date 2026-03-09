#!/bin/bash
echo "=== Exporting restore_trashed_cases Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
take_screenshot /tmp/restore_task_final.png

# Load target IDs
if [ -f /tmp/trashed_ids_info.txt ]; then
    source /tmp/trashed_ids_info.txt
else
    echo "ERROR: Target IDs file not found"
    ID_BROWN=""
    ID_MIRANDA=""
    ID_GIDEON=""
fi

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Create empty failure result
    cat > /tmp/restore_trashed_cases_result.json << EOF
{"error": "DB not found", "passed": false}
EOF
    exit 1
fi

# Helper function to check item status
check_item_status() {
    local item_id=$1
    if [ -z "$item_id" ]; then
        echo '{"status": "unknown"}'
        return
    fi
    
    # Check if exists in items table (not permanently deleted)
    local exists=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemID=$item_id" 2>/dev/null)
    
    # Check if exists in deletedItems table (still in trash)
    local is_trashed=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM deletedItems WHERE itemID=$item_id" 2>/dev/null)
    
    # Check metadata integrity (Case Name)
    local name=$(sqlite3 "$JURISM_DB" "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemID=$item_id AND fieldID=58 LIMIT 1" 2>/dev/null)
    
    # JSON output for this item
    # escape name quotes
    local safe_name=$(echo "$name" | sed 's/"/\\"/g')
    echo "{\"id\": $item_id, \"exists\": $exists, \"is_trashed\": $is_trashed, \"name\": \"$safe_name\"}"
}

echo "Checking status of target items..."
STATUS_BROWN=$(check_item_status "$ID_BROWN")
STATUS_MIRANDA=$(check_item_status "$ID_MIRANDA")
STATUS_GIDEON=$(check_item_status "$ID_GIDEON")

# Check Data Loss / Integrity
# Current active items (not in trash)
CURRENT_ACTIVE_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "0")
INITIAL_ACTIVE_COUNT=$(cat /tmp/initial_active_count 2>/dev/null || echo "0")

# Total items (including trash) - should verify no permanent deletions
CURRENT_TOTAL=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")

echo "Counts: Initial Active=$INITIAL_ACTIVE_COUNT, Current Active=$CURRENT_ACTIVE_COUNT, Current Total=$CURRENT_TOTAL"

# Construct JSON result
cat > /tmp/restore_trashed_cases_result.json << EOF
{
    "brown": $STATUS_BROWN,
    "miranda": $STATUS_MIRANDA,
    "gideon": $STATUS_GIDEON,
    "initial_active_count": $INITIAL_ACTIVE_COUNT,
    "current_active_count": $CURRENT_ACTIVE_COUNT,
    "current_total_count": $CURRENT_TOTAL,
    "screenshot_path": "/tmp/restore_task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Permission fix
chmod 666 /tmp/restore_trashed_cases_result.json 2>/dev/null || true

echo "Result saved to /tmp/restore_trashed_cases_result.json"
cat /tmp/restore_trashed_cases_result.json
echo "=== Export Complete ==="