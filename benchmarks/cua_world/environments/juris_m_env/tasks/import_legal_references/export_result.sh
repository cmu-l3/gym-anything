#!/bin/bash
# Export script for import_legal_references task
echo "=== Exporting import_legal_references Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/import_final.png
echo "Screenshot saved"

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/import_legal_references_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# Count items added (after setup cleared to 0)
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "Total items in library: $ITEM_COUNT"

# Count items added during task (dateAdded > task_start)
if [ "$TASK_START" -gt 0 ] 2>/dev/null; then
    TASK_START_DT=$(date -d "@$TASK_START" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "1970-01-01 00:00:00")
    ITEMS_ADDED=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31) AND dateAdded > '$TASK_START_DT'" 2>/dev/null || echo "0")
else
    ITEMS_ADDED="$ITEM_COUNT"
    TASK_START_DT="1970-01-01 00:00:00"
fi
echo "Items added during task: $ITEMS_ADDED"

# Check for expected case names
BROWN=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items JOIN itemData ON items.itemID=itemData.itemID JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE fieldID IN (1,58) AND LOWER(value) LIKE '%brown%board%'" 2>/dev/null || echo "0")
MIRANDA=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items JOIN itemData ON items.itemID=itemData.itemID JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE fieldID IN (1,58) AND LOWER(value) LIKE '%miranda%arizona%'" 2>/dev/null || echo "0")
MARBURY=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items JOIN itemData ON items.itemID=itemData.itemID JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE fieldID IN (1,58) AND LOWER(value) LIKE '%marbury%madison%'" 2>/dev/null || echo "0")
echo "Case matches: Brown=$BROWN, Miranda=$MIRANDA, Marbury=$MARBURY"

# Get list of titles (first 15)
TITLES=$(sqlite3 "$JURISM_DB" "SELECT DISTINCT value FROM items JOIN itemData ON items.itemID=itemData.itemID JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemTypeID NOT IN (1,3,31) AND fieldID IN (1,58) LIMIT 15" 2>/dev/null | tr '\n' '|' || echo "")
echo "Item titles: $TITLES"

# Build JSON result
cat > /tmp/import_legal_references_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_start_datetime": "$TASK_START_DT",
    "item_count": $ITEM_COUNT,
    "items_added_during_task": $ITEMS_ADDED,
    "case_brown_v_board": $BROWN,
    "case_miranda_v_arizona": $MIRANDA,
    "case_marbury_v_madison": $MARBURY,
    "titles_sample": "$(echo "$TITLES" | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/import_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/import_legal_references_result.json 2>/dev/null || true
echo "Result saved to /tmp/import_legal_references_result.json"
cat /tmp/import_legal_references_result.json
echo "=== Export Complete ==="
