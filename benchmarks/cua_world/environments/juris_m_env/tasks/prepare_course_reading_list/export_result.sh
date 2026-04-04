#!/bin/bash
echo "=== Exporting prepare_course_reading_list results ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JURISM_DB=$(get_jurism_db)
OUTPUT_FILE="/home/ga/Documents/week1_syllabus.html"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Verify Collection
COLL_ID=$(sqlite3 "$JURISM_DB" "SELECT collectionID FROM collections WHERE collectionName = 'Week 1 - Judicial Review' LIMIT 1" 2>/dev/null || echo "")
COLL_EXISTS="false"
ITEM_COUNT=0
HAS_MARBURY="false"
HAS_ARTICLE="false"

if [ -n "$COLL_ID" ]; then
    COLL_EXISTS="true"
    # Count items in this collection
    ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM collectionItems WHERE collectionID = $COLL_ID" 2>/dev/null || echo "0")
    
    # Check for Marbury v. Madison (using partial match on caseName/title fields)
    MARBURY_COUNT=$(sqlite3 "$JURISM_DB" "
        SELECT COUNT(*) FROM collectionItems ci
        JOIN itemData id ON ci.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        WHERE ci.collectionID = $COLL_ID 
        AND (id.fieldID = 58 OR id.fieldID = 1) -- caseName or title
        AND idv.value LIKE '%Marbury%Madison%'
    " 2>/dev/null || echo "0")
    [ "$MARBURY_COUNT" -gt 0 ] && HAS_MARBURY="true"

    # Check for Constitutional Fact Review
    ARTICLE_COUNT=$(sqlite3 "$JURISM_DB" "
        SELECT COUNT(*) FROM collectionItems ci
        JOIN itemData id ON ci.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        WHERE ci.collectionID = $COLL_ID 
        AND id.fieldID = 1 -- title
        AND idv.value LIKE '%Constitutional Fact Review%'
    " 2>/dev/null || echo "0")
    [ "$ARTICLE_COUNT" -gt 0 ] && HAS_ARTICLE="true"
fi

# 2. Verify Note
# Look for a note containing "original jurisdiction" attached to Marbury
NOTE_FOUND="false"
NOTE_TEXT=""
MARBURY_ITEM_ID=$(sqlite3 "$JURISM_DB" "
    SELECT items.itemID FROM items
    JOIN itemData id ON items.itemID = id.itemID
    JOIN itemDataValues idv ON id.valueID = idv.valueID
    WHERE (id.fieldID = 58 OR id.fieldID = 1)
    AND idv.value LIKE '%Marbury%Madison%'
    LIMIT 1
" 2>/dev/null || echo "")

if [ -n "$MARBURY_ITEM_ID" ]; then
    NOTE_TEXT=$(sqlite3 "$JURISM_DB" "
        SELECT note FROM itemNotes 
        WHERE parentItemID = $MARBURY_ITEM_ID 
        AND note LIKE '%original jurisdiction%'
        LIMIT 1
    " 2>/dev/null || echo "")
    if [ -n "$NOTE_TEXT" ]; then
        NOTE_FOUND="true"
    fi
fi

# 3. Verify Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT_VALID="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Check if file contains the instruction text (proof it's the correct report)
    if grep -q "original jurisdiction" "$OUTPUT_FILE"; then
        FILE_CONTENT_VALID="true"
    fi
fi

# Export JSON
cat > /tmp/task_result.json <<EOF
{
    "collection_exists": $COLL_EXISTS,
    "collection_item_count": $ITEM_COUNT,
    "has_marbury": $HAS_MARBURY,
    "has_article": $HAS_ARTICLE,
    "note_found": $NOTE_FOUND,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_valid": $FILE_CONTENT_VALID,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json