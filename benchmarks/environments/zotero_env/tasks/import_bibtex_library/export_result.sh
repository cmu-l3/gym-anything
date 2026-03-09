#!/bin/bash
echo "=== Exporting import_bibtex_library task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get Zotero database path
ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_item_count 2>/dev/null || echo "0")

# Get current count
if [ -f "$ZOTERO_DB" ]; then
    CURRENT_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID != 14 AND itemTypeID != 1" 2>/dev/null || echo "0")
else
    CURRENT_COUNT="0"
fi

ITEMS_ADDED=$((CURRENT_COUNT - INITIAL_COUNT))

# Check if expected authors are in database
FOUND_AUTHORS=""
if [ -f "$ZOTERO_DB" ]; then
    # Check for Einstein
    EINSTEIN=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM creators WHERE lastName LIKE '%Einstein%'" 2>/dev/null || echo "0")
    # Check for Turing
    TURING=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM creators WHERE lastName LIKE '%Turing%'" 2>/dev/null || echo "0")
    # Check for Knuth
    KNUTH=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM creators WHERE lastName LIKE '%Knuth%'" 2>/dev/null || echo "0")
    # Check for Shannon
    SHANNON=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM creators WHERE lastName LIKE '%Shannon%'" 2>/dev/null || echo "0")

    FOUND_AUTHORS="Einstein:$EINSTEIN,Turing:$TURING,Knuth:$KNUTH,Shannon:$SHANNON"
fi

# Check for BibTeX-specific fields (to confirm it was imported, not manually added)
BIBTEX_IMPORTED="false"
RECENT_ITEMS=0
if [ -f "$ZOTERO_DB" ] && [ "$ITEMS_ADDED" -gt 0 ]; then
    # Check for items added in the last 5 minutes (more reliable than just count)
    # Get timestamp from 5 minutes ago in SQLite format
    RECENT_ITEMS=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID != 14 AND itemTypeID != 1 AND dateAdded >= datetime('now', '-5 minutes')" 2>/dev/null || echo "0")

    # If items were added recently and match expected count
    if [ "$ITEMS_ADDED" -ge 9 ] && [ "$ITEMS_ADDED" -le 11 ] && [ "$RECENT_ITEMS" -ge 9 ]; then
        BIBTEX_IMPORTED="true"
    fi
fi

# Create temp JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "items_added": $ITEMS_ADDED,
    "recent_items": $RECENT_ITEMS,
    "bibtex_imported": $BIBTEX_IMPORTED,
    "found_authors": "$FOUND_AUTHORS",
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
