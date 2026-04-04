#!/bin/bash
echo "=== Exporting attach_web_link_to_case Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/attach_final.png
echo "Screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    cat > /tmp/task_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

# 1. Find the Gideon v. Wainwright case ID
# fieldID 58 is caseName (verified in utils/inject_references.py)
# fieldID 1 is title (fallback if user somehow changed type)
GIDEON_ID=$(sqlite3 "$JURISM_DB" "
SELECT items.itemID FROM items
JOIN itemData ON items.itemID = itemData.itemID
JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
WHERE fieldID IN (1, 58) AND LOWER(value) LIKE '%gideon%wainwright%'
LIMIT 1" 2>/dev/null || echo "")

echo "Gideon Case ID: $GIDEON_ID"

ATTACHMENT_FOUND="false"
ATTACHMENT_URL=""
ATTACHMENT_TITLE=""
LINK_MODE=""
IS_CHILD="false"
CREATED_DURING_TASK="false"

if [ -n "$GIDEON_ID" ]; then
    # 2. Look for attachments (itemTypeID=1) that are children of Gideon
    # We check itemAttachments table for parentItemID
    # Zotero schema: itemAttachments table has (itemID, parentItemID, linkMode, contentType, charset, path, syncState)
    
    # Query for the attachment details
    # We look for the most recently added attachment to this parent
    ATTACHMENT_DATA=$(sqlite3 "$JURISM_DB" "
    SELECT ia.itemID, ia.path, ia.linkMode, i.dateAdded
    FROM itemAttachments ia
    JOIN items i ON ia.itemID = i.itemID
    WHERE ia.parentItemID = $GIDEON_ID
    ORDER BY i.dateAdded DESC
    LIMIT 1" 2>/dev/null || echo "")

    if [ -n "$ATTACHMENT_DATA" ]; then
        ATTACHMENT_FOUND="true"
        IS_CHILD="true"
        
        # Parse result (pipe separated)
        ATT_ID=$(echo "$ATTACHMENT_DATA" | awk -F'|' '{print $1}')
        ATTACHMENT_URL=$(echo "$ATTACHMENT_DATA" | awk -F'|' '{print $2}')
        LINK_MODE=$(echo "$ATTACHMENT_DATA" | awk -F'|' '{print $3}')
        DATE_ADDED=$(echo "$ATTACHMENT_DATA" | awk -F'|' '{print $4}')
        
        echo "Attachment Found: ID=$ATT_ID, Mode=$LINK_MODE, URL=$ATTACHMENT_URL"
        
        # Check Title (title is stored in itemData/itemDataValues for the attachment item)
        # fieldID 1 is title
        ATTACHMENT_TITLE=$(sqlite3 "$JURISM_DB" "
        SELECT value FROM itemData
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        WHERE itemID = $ATT_ID AND fieldID = 1
        LIMIT 1" 2>/dev/null || echo "")
        
        echo "Attachment Title: $ATTACHMENT_TITLE"
        
        # Check timestamp
        if [ "$TASK_START" -gt 0 ]; then
            TASK_START_DT=$(date -d "@$TASK_START" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "1970-01-01")
            if [[ "$DATE_ADDED" > "$TASK_START_DT" ]]; then
                CREATED_DURING_TASK="true"
            fi
        fi
    else
        echo "No attachments found for Gideon ID $GIDEON_ID"
    fi
else
    echo "Gideon v. Wainwright case not found in database"
fi

# Escape for JSON
URL_ESC=$(echo "$ATTACHMENT_URL" | sed 's/"/\\"/g')
TITLE_ESC=$(echo "$ATTACHMENT_TITLE" | sed 's/"/\\"/g')

cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "target_case_found": $([ -n "$GIDEON_ID" ] && echo "true" || echo "false"),
    "attachment_found": $ATTACHMENT_FOUND,
    "attachment_is_child": $IS_CHILD,
    "link_mode": "${LINK_MODE:-unknown}",
    "attachment_url": "$URL_ESC",
    "attachment_title": "$TITLE_ESC",
    "created_during_task": $CREATED_DURING_TASK,
    "screenshot_path": "/tmp/attach_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="