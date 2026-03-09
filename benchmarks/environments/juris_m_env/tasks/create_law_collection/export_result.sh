#!/bin/bash
# Export script for create_law_collection task
echo "=== Exporting create_law_collection Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/collection_final.png
echo "Screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/create_law_collection_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# Count collections created
COLLECTION_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM collections" 2>/dev/null || echo "0")
echo "Total collections: $COLLECTION_COUNT"

# Get collection names and their item counts
COLLECTION_DATA=$(sqlite3 "$JURISM_DB" "SELECT c.collectionName, COUNT(ci.itemID) as cnt FROM collections c LEFT JOIN collectionItems ci ON c.collectionID=ci.collectionID LEFT JOIN items i ON ci.itemID=i.itemID AND i.itemTypeID NOT IN (1,3,31) GROUP BY c.collectionID ORDER BY cnt DESC LIMIT 10" 2>/dev/null || echo "")
echo "Collections: $COLLECTION_DATA"

# Check largest collection item count
MAX_ITEMS=$(sqlite3 "$JURISM_DB" "SELECT MAX(cnt) FROM (SELECT COUNT(i.itemID) as cnt FROM collections c LEFT JOIN collectionItems ci ON c.collectionID=ci.collectionID LEFT JOIN items i ON ci.itemID=i.itemID AND i.itemTypeID NOT IN (1,3,31) GROUP BY c.collectionID)" 2>/dev/null || echo "0")
echo "Max items in any collection: $MAX_ITEMS"

# First collection name
FIRST_COLL_NAME=$(sqlite3 "$JURISM_DB" "SELECT collectionName FROM collections ORDER BY dateAdded DESC LIMIT 1" 2>/dev/null || echo "")
echo "Most recent collection: $FIRST_COLL_NAME"

# Escape for JSON
FIRST_COLL_NAME_ESC=$(echo "$FIRST_COLL_NAME" | sed 's/"/\\"/g')
COLLECTION_DATA_ESC=$(echo "$COLLECTION_DATA" | sed 's/"/\\"/g' | tr '\n' '|')

cat > /tmp/create_law_collection_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "collection_count": $COLLECTION_COUNT,
    "max_items_in_collection": ${MAX_ITEMS:-0},
    "most_recent_collection": "$FIRST_COLL_NAME_ESC",
    "collection_summary": "$COLLECTION_DATA_ESC",
    "screenshot_path": "/tmp/collection_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/create_law_collection_result.json 2>/dev/null || true
echo "Result saved to /tmp/create_law_collection_result.json"
cat /tmp/create_law_collection_result.json
echo "=== Export Complete ==="
