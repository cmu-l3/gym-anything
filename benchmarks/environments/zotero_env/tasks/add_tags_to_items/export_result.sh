#!/bin/bash
echo "=== Exporting add_tags_to_items task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get Zotero database path
ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"

# Get initial counts
INITIAL_TAG_COUNT=$(cat /tmp/initial_tag_count 2>/dev/null || echo "0")
INITIAL_TAGGED_ITEMS=$(cat /tmp/initial_tagged_items 2>/dev/null || echo "0")

# Get current counts
if [ -f "$ZOTERO_DB" ]; then
    CURRENT_TAG_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(DISTINCT tagID) FROM itemTags" 2>/dev/null || echo "0")
    CURRENT_TAGGED_ITEMS=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(DISTINCT itemID) FROM itemTags" 2>/dev/null || echo "0")

    # Get ALL tags (not just sample) - needed for relevance checking
    ALL_TAGS=$(sqlite3 "$ZOTERO_DB" "SELECT name FROM tags" 2>/dev/null | tr '\n' ',' || echo "")
else
    CURRENT_TAG_COUNT="0"
    CURRENT_TAGGED_ITEMS="0"
    ALL_TAGS=""
fi

TAGS_ADDED=$((CURRENT_TAG_COUNT - INITIAL_TAG_COUNT))
TAGGED_ITEMS_ADDED=$((CURRENT_TAGGED_ITEMS - INITIAL_TAGGED_ITEMS))

# Create temp JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_tag_count": $INITIAL_TAG_COUNT,
    "current_tag_count": $CURRENT_TAG_COUNT,
    "tags_added": $TAGS_ADDED,
    "initial_tagged_items": $INITIAL_TAGGED_ITEMS,
    "current_tagged_items": $CURRENT_TAGGED_ITEMS,
    "tagged_items_added": $TAGGED_ITEMS_ADDED,
    "all_tags": "$ALL_TAGS",
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
