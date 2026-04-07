#!/bin/bash
# Export script for Add Referral Source Option task

echo "=== Exporting Add Referral Source Option Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_refsource_count.txt 2>/dev/null || echo "0")

# Get current referral source count
CURRENT_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM list_options WHERE list_id='refsource'" 2>/dev/null || echo "0")

echo "Referral source count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Query for the Westside Urgent Care option (case-insensitive search)
echo ""
echo "=== Searching for Westside Urgent Care option ==="

WESTSIDE_OPTION=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT option_id, title, list_id, activity, seq, notes 
     FROM list_options 
     WHERE list_id='refsource' 
     AND (LOWER(title) LIKE '%westside%' OR LOWER(option_id) LIKE '%westside%')
     LIMIT 1" 2>/dev/null)

# Initialize variables
OPTION_FOUND="false"
OPTION_ID=""
OPTION_TITLE=""
OPTION_LIST_ID=""
OPTION_ACTIVITY=""
OPTION_SEQ=""
OPTION_NOTES=""

if [ -n "$WESTSIDE_OPTION" ]; then
    OPTION_FOUND="true"
    OPTION_ID=$(echo "$WESTSIDE_OPTION" | cut -f1)
    OPTION_TITLE=$(echo "$WESTSIDE_OPTION" | cut -f2)
    OPTION_LIST_ID=$(echo "$WESTSIDE_OPTION" | cut -f3)
    OPTION_ACTIVITY=$(echo "$WESTSIDE_OPTION" | cut -f4)
    OPTION_SEQ=$(echo "$WESTSIDE_OPTION" | cut -f5)
    OPTION_NOTES=$(echo "$WESTSIDE_OPTION" | cut -f6)
    
    echo "Found Westside option:"
    echo "  Option ID: $OPTION_ID"
    echo "  Title: $OPTION_TITLE"
    echo "  List ID: $OPTION_LIST_ID"
    echo "  Active: $OPTION_ACTIVITY"
    echo "  Sequence: $OPTION_SEQ"
else
    echo "Westside Urgent Care option NOT found"
    
    # Debug: show all current referral sources
    echo ""
    echo "Current referral source options:"
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "SELECT option_id, title, activity FROM list_options WHERE list_id='refsource' ORDER BY seq" 2>/dev/null || true
fi

# Check if any new options were added (even if not Westside)
NEW_OPTIONS_COUNT=$((CURRENT_COUNT - INITIAL_COUNT))
echo ""
echo "New options added: $NEW_OPTIONS_COUNT"

# Check for options added in wrong list
WRONG_LIST_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT list_id, option_id, title 
     FROM list_options 
     WHERE LOWER(title) LIKE '%westside%' AND list_id != 'refsource'
     LIMIT 1" 2>/dev/null)

WRONG_LIST_FOUND="false"
WRONG_LIST_ID=""
if [ -n "$WRONG_LIST_CHECK" ]; then
    WRONG_LIST_FOUND="true"
    WRONG_LIST_ID=$(echo "$WRONG_LIST_CHECK" | cut -f1)
    echo "WARNING: Westside option found in wrong list: $WRONG_LIST_ID"
fi

# Validate option properties
TITLE_CORRECT="false"
if echo "$OPTION_TITLE" | grep -qi "westside"; then
    if echo "$OPTION_TITLE" | grep -qi "urgent"; then
        TITLE_CORRECT="true"
    fi
fi

LIST_CORRECT="false"
if [ "$OPTION_LIST_ID" = "refsource" ]; then
    LIST_CORRECT="true"
fi

OPTION_ACTIVE="false"
if [ "$OPTION_ACTIVITY" = "1" ]; then
    OPTION_ACTIVE="true"
fi

OPTION_USABLE="false"
if [ -n "$OPTION_ID" ] && [ "$OPTION_ID" != "NULL" ]; then
    OPTION_USABLE="true"
fi

# Escape special characters for JSON
OPTION_TITLE_ESCAPED=$(echo "$OPTION_TITLE" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr -d '\n')
OPTION_ID_ESCAPED=$(echo "$OPTION_ID" | sed 's/"/\\"/g' | tr -d '\n')
OPTION_NOTES_ESCAPED=$(echo "$OPTION_NOTES" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr -d '\n')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/refsource_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "new_options_added": ${NEW_OPTIONS_COUNT:-0},
    "option_found": $OPTION_FOUND,
    "option": {
        "option_id": "$OPTION_ID_ESCAPED",
        "title": "$OPTION_TITLE_ESCAPED",
        "list_id": "$OPTION_LIST_ID",
        "activity": "$OPTION_ACTIVITY",
        "seq": "$OPTION_SEQ",
        "notes": "$OPTION_NOTES_ESCAPED"
    },
    "validation": {
        "title_correct": $TITLE_CORRECT,
        "list_correct": $LIST_CORRECT,
        "option_active": $OPTION_ACTIVE,
        "option_usable": $OPTION_USABLE
    },
    "wrong_list_found": $WRONG_LIST_FOUND,
    "wrong_list_id": "$WRONG_LIST_ID",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result to standard location
rm -f /tmp/add_refsource_result.json 2>/dev/null || sudo rm -f /tmp/add_refsource_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_refsource_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_refsource_result.json
chmod 666 /tmp/add_refsource_result.json 2>/dev/null || sudo chmod 666 /tmp/add_refsource_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/add_refsource_result.json"
cat /tmp/add_refsource_result.json
echo ""
echo "=== Export Complete ==="