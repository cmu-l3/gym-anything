#!/bin/bash
echo "=== Exporting merge_duplicate_cases results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get Database Path
DB_PATH=$(get_jurism_db)

# 1. Check Active Item Count (Should be 10)
ACTIVE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemID NOT IN (SELECT itemID FROM deletedItems) AND itemTypeID NOT IN (1, 3, 14, 31)" 2>/dev/null || echo "0")

# 2. Check Deleted Item Count (Should increase by at least 3)
INITIAL_DELETED=$(cat /tmp/initial_deleted.txt 2>/dev/null || echo "0")
CURRENT_DELETED=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM deletedItems" 2>/dev/null || echo "0")
DELETED_DIFF=$((CURRENT_DELETED - INITIAL_DELETED))

# 3. Check for Duplicate Names in Active Items (Should be 0)
DUPLICATE_GROUPS=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM (
        SELECT v.value 
        FROM items i 
        JOIN itemData d ON i.itemID = d.itemID 
        JOIN itemDataValues v ON d.valueID = v.valueID 
        WHERE i.itemID NOT IN (SELECT itemID FROM deletedItems) 
        AND i.itemTypeID NOT IN (1, 3, 14, 31) 
        AND d.fieldID = 58 
        GROUP BY v.value 
        HAVING COUNT(*) > 1
    )
" 2>/dev/null || echo "0")

# 4. Check Metadata Integrity of the target cases
# Brown v. Board should have full abstract
BROWN_ABSTRACT=$(sqlite3 "$DB_PATH" "SELECT v.value FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=2 AND i.itemID IN (SELECT itemID FROM itemData d2 JOIN itemDataValues v2 ON d2.valueID=v2.valueID WHERE d2.fieldID=58 AND v2.value='Brown v. Board of Education') AND i.itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "")

# Miranda should have an abstract (non-empty)
MIRANDA_ABSTRACT=$(sqlite3 "$DB_PATH" "SELECT v.value FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=2 AND i.itemID IN (SELECT itemID FROM itemData d2 JOIN itemDataValues v2 ON d2.valueID=v2.valueID WHERE d2.fieldID=58 AND v2.value='Miranda v. Arizona') AND i.itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "")

# Gideon should have a court
GIDEON_COURT=$(sqlite3 "$DB_PATH" "SELECT v.value FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=60 AND i.itemID IN (SELECT itemID FROM itemData d2 JOIN itemDataValues v2 ON d2.valueID=v2.valueID WHERE d2.fieldID=58 AND v2.value='Gideon v. Wainwright') AND i.itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "")

# Escape strings for JSON
BROWN_ESC=$(echo "$BROWN_ABSTRACT" | sed 's/"/\\"/g' | tr '\n' ' ')
MIRANDA_ESC=$(echo "$MIRANDA_ABSTRACT" | sed 's/"/\\"/g' | tr '\n' ' ')
GIDEON_ESC=$(echo "$GIDEON_COURT" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create JSON Result
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "active_item_count": $ACTIVE_COUNT,
    "deleted_items_increase": $DELETED_DIFF,
    "duplicate_groups_count": $DUPLICATE_GROUPS,
    "metadata_checks": {
        "brown_abstract": "$BROWN_ESC",
        "miranda_abstract": "$MIRANDA_ESC",
        "gideon_court": "$GIDEON_ESC"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="