#!/bin/bash
# Export script for add_manual_case task
echo "=== Exporting add_manual_case Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/manual_case_final.png
echo "Screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_item_count_manual 2>/dev/null || echo "0")

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/add_manual_case_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# Check for Roe v. Wade (fieldID=58 is caseName)
ROE_ID=$(sqlite3 "$JURISM_DB" "SELECT items.itemID FROM items JOIN itemData ON items.itemID=itemData.itemID JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE fieldID=58 AND LOWER(value) LIKE '%roe%wade%' LIMIT 1" 2>/dev/null || echo "")
ROE_FOUND="false"
ROE_COURT=""
ROE_DATE=""
ROE_REPORTER=""
ROE_VOLUME=""
ROE_PAGE=""
CREATED_DURING_TASK="false"

if [ -n "$ROE_ID" ]; then
    ROE_FOUND="true"
    echo "Found Roe v. Wade with itemID=$ROE_ID"

    # Get court (fieldID=60)
    ROE_COURT=$(sqlite3 "$JURISM_DB" "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemID=$ROE_ID AND fieldID=60 LIMIT 1" 2>/dev/null || echo "")
    # Get dateDecided (fieldID=69)
    ROE_DATE=$(sqlite3 "$JURISM_DB" "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemID=$ROE_ID AND fieldID=69 LIMIT 1" 2>/dev/null || echo "")
    # reporter (fieldID=49)
    ROE_REPORTER=$(sqlite3 "$JURISM_DB" "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemID=$ROE_ID AND fieldID=49 LIMIT 1" 2>/dev/null || echo "")
    # reporterVolume (fieldID=66)
    ROE_VOLUME=$(sqlite3 "$JURISM_DB" "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemID=$ROE_ID AND fieldID=66 LIMIT 1" 2>/dev/null || echo "")
    # firstPage (fieldID=67)
    ROE_PAGE=$(sqlite3 "$JURISM_DB" "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemID=$ROE_ID AND fieldID=67 LIMIT 1" 2>/dev/null || echo "")

    echo "  Court: $ROE_COURT"
    echo "  Date: $ROE_DATE"
    echo "  Reporter: $ROE_REPORTER  Volume: $ROE_VOLUME  Page: $ROE_PAGE"

    # Check if added during task
    if [ "$TASK_START" -gt 0 ] 2>/dev/null; then
        TASK_START_DT=$(date -d "@$TASK_START" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "1970-01-01 00:00:00")
        ADDED_AFTER=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemID=$ROE_ID AND dateAdded > '$TASK_START_DT'" 2>/dev/null || echo "0")
        [ "$ADDED_AFTER" -gt 0 ] && CREATED_DURING_TASK="true"
    fi
fi

CURRENT_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")

# Escape values for JSON
ROE_COURT_ESC=$(echo "$ROE_COURT" | sed 's/"/\\"/g')
ROE_DATE_ESC=$(echo "$ROE_DATE" | sed 's/"/\\"/g')

cat > /tmp/add_manual_case_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_item_count": $INITIAL_COUNT,
    "current_item_count": $CURRENT_COUNT,
    "roe_found": $ROE_FOUND,
    "created_during_task": $CREATED_DURING_TASK,
    "roe": {
        "item_id": "${ROE_ID:-}",
        "court": "$ROE_COURT_ESC",
        "date_decided": "$ROE_DATE_ESC",
        "reporter": "$(echo "$ROE_REPORTER" | sed 's/"/\\"/g')",
        "volume": "$(echo "$ROE_VOLUME" | sed 's/"/\\"/g')",
        "first_page": "$(echo "$ROE_PAGE" | sed 's/"/\\"/g')"
    },
    "screenshot_path": "/tmp/manual_case_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/add_manual_case_result.json 2>/dev/null || true
echo "Result saved to /tmp/add_manual_case_result.json"
cat /tmp/add_manual_case_result.json
echo "=== Export Complete ==="
