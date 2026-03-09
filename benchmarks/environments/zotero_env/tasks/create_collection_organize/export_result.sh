#!/bin/bash
echo "=== Exporting create_collection_organize task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get Zotero database path
ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"

# Get initial counts
INITIAL_COLL_COUNT=$(cat /tmp/initial_collection_count 2>/dev/null || echo "0")
INITIAL_ITEM_COUNT=$(cat /tmp/initial_item_count 2>/dev/null || echo "0")

# Get current counts
if [ -f "$ZOTERO_DB" ]; then
    CURRENT_COLL_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM collections" 2>/dev/null || echo "0")
    CURRENT_ITEM_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID != 14 AND itemTypeID != 1" 2>/dev/null || echo "0")
else
    CURRENT_COLL_COUNT="0"
    CURRENT_ITEM_COUNT="0"
fi

COLLECTIONS_ADDED=$((CURRENT_COLL_COUNT - INITIAL_COLL_COUNT))
ITEMS_ADDED=$((CURRENT_ITEM_COUNT - INITIAL_ITEM_COUNT))

# Check for collection named "Machine Learning Papers"
COLLECTION_FOUND="false"
COLLECTION_ID=""
ITEMS_IN_COLLECTION=0

if [ -f "$ZOTERO_DB" ]; then
    # Exact match for collection name (case-insensitive)
    COLLECTION_ID=$(sqlite3 "$ZOTERO_DB" "SELECT collectionID FROM collections WHERE LOWER(collectionName) = LOWER('Machine Learning Papers')" 2>/dev/null | head -1)

    if [ -n "$COLLECTION_ID" ]; then
        COLLECTION_FOUND="true"
        # Count items in this collection
        ITEMS_IN_COLLECTION=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM collectionItems WHERE collectionID = $COLLECTION_ID" 2>/dev/null || echo "0")
    fi
fi

# Create temp JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_collection_count": $INITIAL_COLL_COUNT,
    "current_collection_count": $CURRENT_COLL_COUNT,
    "collections_added": $COLLECTIONS_ADDED,
    "initial_item_count": $INITIAL_ITEM_COUNT,
    "current_item_count": $CURRENT_ITEM_COUNT,
    "items_added": $ITEMS_ADDED,
    "collection_found": $COLLECTION_FOUND,
    "collection_id": "$COLLECTION_ID",
    "items_in_collection": $ITEMS_IN_COLLECTION,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
