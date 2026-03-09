#!/bin/bash
# Export script for add_note_to_case task
echo "=== Exporting add_note_to_case Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/note_final.png
echo "Screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/add_note_to_case_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# Count notes (itemTypeID=31 in Jurism 6)
NOTE_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM itemNotes" 2>/dev/null || echo "0")
echo "Total notes: $NOTE_COUNT"

# Check for notes attached to Brown v. Board (find its itemID first)
BROWN_ID=$(sqlite3 "$JURISM_DB" "SELECT items.itemID FROM items JOIN itemData ON items.itemID=itemData.itemID JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE fieldID=58 AND LOWER(value) LIKE '%brown%board%' LIMIT 1" 2>/dev/null || echo "0")
echo "Brown v. Board itemID: $BROWN_ID"

NOTES_ON_BROWN=0
NOTE_TITLE=""
NOTE_CONTENT_PREVIEW=""
if [ -n "$BROWN_ID" ] && [ "$BROWN_ID" != "0" ]; then
    NOTES_ON_BROWN=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM itemNotes WHERE parentItemID=$BROWN_ID" 2>/dev/null || echo "0")
    NOTE_TITLE=$(sqlite3 "$JURISM_DB" "SELECT title FROM itemNotes WHERE parentItemID=$BROWN_ID LIMIT 1" 2>/dev/null || echo "")
    NOTE_CONTENT_LEN=$(sqlite3 "$JURISM_DB" "SELECT LENGTH(note) FROM itemNotes WHERE parentItemID=$BROWN_ID LIMIT 1" 2>/dev/null || echo "0")
    echo "Notes on Brown v. Board: $NOTES_ON_BROWN (title: $NOTE_TITLE, content_len: $NOTE_CONTENT_LEN)"
fi

# Any notes on any item
NOTES_WITH_PARENT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM itemNotes WHERE parentItemID IS NOT NULL AND parentItemID != 0" 2>/dev/null || echo "0")
echo "Notes with parent items: $NOTES_WITH_PARENT"

NOTE_TITLE_ESC=$(echo "$NOTE_TITLE" | sed 's/"/\\"/g')

cat > /tmp/add_note_to_case_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "note_count": $NOTE_COUNT,
    "notes_with_parent": $NOTES_WITH_PARENT,
    "brown_item_id": ${BROWN_ID:-0},
    "notes_on_brown_v_board": $NOTES_ON_BROWN,
    "note_title": "$NOTE_TITLE_ESC",
    "note_content_length": ${NOTE_CONTENT_LEN:-0},
    "screenshot_path": "/tmp/note_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/add_note_to_case_result.json 2>/dev/null || true
echo "Result saved to /tmp/add_note_to_case_result.json"
cat /tmp/add_note_to_case_result.json
echo "=== Export Complete ==="
