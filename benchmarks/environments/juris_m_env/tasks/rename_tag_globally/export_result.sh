#!/bin/bash
echo "=== Exporting Rename Tag Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DB_PATH=$(get_jurism_db)

if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    cat > /tmp/task_result.json <<EOF
{
    "error": "Database not found",
    "passed": false
}
EOF
    exit 1
fi

# ------------------------------------------------------------------
# CHECK DATABASE STATE
# ------------------------------------------------------------------

# 1. Check if new tag exists
NEW_TAG_NAME="Equal Protection Clause"
NEW_TAG_ID=$(sqlite3 "$DB_PATH" "SELECT tagID FROM tags WHERE name='$NEW_TAG_NAME'" 2>/dev/null || echo "")
NEW_TAG_EXISTS="false"
if [ -n "$NEW_TAG_ID" ]; then
    NEW_TAG_EXISTS="true"
fi

# 2. Count items with new tag
NEW_TAG_ITEM_COUNT=0
if [ -n "$NEW_TAG_ID" ]; then
    NEW_TAG_ITEM_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM itemTags WHERE tagID=$NEW_TAG_ID" 2>/dev/null || echo "0")
fi

# 3. Check if old tag still exists or has items
OLD_TAG_NAME="Equal Protection"
OLD_TAG_ID=$(sqlite3 "$DB_PATH" "SELECT tagID FROM tags WHERE name='$OLD_TAG_NAME'" 2>/dev/null || echo "")
OLD_TAG_EXISTS="false"
OLD_TAG_ITEM_COUNT=0

if [ -n "$OLD_TAG_ID" ]; then
    OLD_TAG_EXISTS="true"
    OLD_TAG_ITEM_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM itemTags WHERE tagID=$OLD_TAG_ID" 2>/dev/null || echo "0")
fi

# 4. Check if specific original items were migrated
# Read the list of IDs we saved during setup
MIGRATED_COUNT=0
TOTAL_ORIGINAL_ITEMS=0
MIGRATION_DETAILS=""

if [ -f /tmp/initial_ep_item_ids.txt ] && [ -n "$NEW_TAG_ID" ]; then
    while read -r ITEM_ID; do
        TOTAL_ORIGINAL_ITEMS=$((TOTAL_ORIGINAL_ITEMS + 1))
        HAS_TAG=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM itemTags WHERE itemID=$ITEM_ID AND tagID=$NEW_TAG_ID" 2>/dev/null || echo "0")
        if [ "$HAS_TAG" -gt 0 ]; then
            MIGRATED_COUNT=$((MIGRATED_COUNT + 1))
        fi
    done < /tmp/initial_ep_item_ids.txt
fi

# 5. Check database modification time (Anti-gaming)
DB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo "0")
DB_MODIFIED="false"
if [ "$DB_MTIME" -gt "$TASK_START" ]; then
    DB_MODIFIED="true"
fi

# 6. Check for collateral damage (ensure other tags still exist)
CONST_LAW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tags WHERE name='Constitutional Law'" 2>/dev/null || echo "0")

# ------------------------------------------------------------------
# GENERATE JSON RESULT
# ------------------------------------------------------------------
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_modified_during_task": $DB_MODIFIED,
    "new_tag_exists": $NEW_TAG_EXISTS,
    "new_tag_id": "${NEW_TAG_ID:-0}",
    "new_tag_item_count": $NEW_TAG_ITEM_COUNT,
    "old_tag_exists": $OLD_TAG_EXISTS,
    "old_tag_item_count": $OLD_TAG_ITEM_COUNT,
    "migrated_item_count": $MIGRATED_COUNT,
    "total_original_items": $TOTAL_ORIGINAL_ITEMS,
    "other_tags_preserved": $((CONST_LAW_COUNT > 0)),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="