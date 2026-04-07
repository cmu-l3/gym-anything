#!/bin/bash
# Export script for Add List Option task
echo "=== Exporting Add List Option Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
take_screenshot /tmp/task_final_state.png
echo "Final screenshot saved to /tmp/task_final_state.png"

# Get initial counts
INITIAL_COUNT=$(cat /tmp/initial_ethnicity_count.txt 2>/dev/null || echo "0")
INITIAL_HAITIAN=$(cat /tmp/initial_haitian_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM list_options WHERE list_id IN ('ethrace', 'ethnicity', 'race')" 2>/dev/null || echo "0")

CURRENT_HAITIAN=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM list_options WHERE (list_id IN ('ethrace', 'ethnicity', 'race')) AND LOWER(title) LIKE '%haitian%'" 2>/dev/null || echo "0")

echo "Option count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"
echo "Haitian count: initial=$INITIAL_HAITIAN, current=$CURRENT_HAITIAN"

# Query for the Haitian option details
echo ""
echo "=== Querying for Haitian ethnicity option ==="
HAITIAN_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT list_id, option_id, title, seq, activity, notes FROM list_options WHERE (list_id IN ('ethrace', 'ethnicity', 'race')) AND LOWER(title) LIKE '%haitian%' ORDER BY option_id DESC LIMIT 1" 2>/dev/null)

# Parse the data
OPTION_FOUND="false"
OPTION_LIST_ID=""
OPTION_ID=""
OPTION_TITLE=""
OPTION_SEQ=""
OPTION_ACTIVE=""
OPTION_NOTES=""

if [ -n "$HAITIAN_DATA" ]; then
    OPTION_FOUND="true"
    OPTION_LIST_ID=$(echo "$HAITIAN_DATA" | cut -f1)
    OPTION_ID=$(echo "$HAITIAN_DATA" | cut -f2)
    OPTION_TITLE=$(echo "$HAITIAN_DATA" | cut -f3)
    OPTION_SEQ=$(echo "$HAITIAN_DATA" | cut -f4)
    OPTION_ACTIVE=$(echo "$HAITIAN_DATA" | cut -f5)
    OPTION_NOTES=$(echo "$HAITIAN_DATA" | cut -f6)
    
    echo "Found Haitian option:"
    echo "  List ID: $OPTION_LIST_ID"
    echo "  Option ID: $OPTION_ID"
    echo "  Title: $OPTION_TITLE"
    echo "  Sequence: $OPTION_SEQ"
    echo "  Active: $OPTION_ACTIVE"
else
    echo "No Haitian option found in database"
fi

# Check if option was newly added (count increased)
NEW_OPTION_ADDED="false"
if [ "$CURRENT_HAITIAN" -gt "$INITIAL_HAITIAN" ]; then
    NEW_OPTION_ADDED="true"
    echo "New Haitian option was added during task"
elif [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    echo "Note: Total option count increased, but Haitian not specifically found"
fi

# Also check for any new options added (for partial credit)
echo ""
echo "=== All ethnicity/race options (post-task) ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT list_id, option_id, title, seq, activity FROM list_options WHERE list_id IN ('ethrace', 'ethnicity', 'race') ORDER BY list_id, seq" 2>/dev/null | head -40
echo "=== End of options ==="

# Check if Firefox/browser is still running
BROWSER_RUNNING="false"
if pgrep -f "firefox" > /dev/null 2>&1; then
    BROWSER_RUNNING="true"
fi

# Escape special characters for JSON
OPTION_TITLE_ESCAPED=$(echo "$OPTION_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')
OPTION_NOTES_ESCAPED=$(echo "$OPTION_NOTES" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/list_option_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_option_count": ${INITIAL_COUNT:-0},
    "current_option_count": ${CURRENT_COUNT:-0},
    "initial_haitian_count": ${INITIAL_HAITIAN:-0},
    "current_haitian_count": ${CURRENT_HAITIAN:-0},
    "option_found": $OPTION_FOUND,
    "new_option_added": $NEW_OPTION_ADDED,
    "option_details": {
        "list_id": "$OPTION_LIST_ID",
        "option_id": "$OPTION_ID",
        "title": "$OPTION_TITLE_ESCAPED",
        "sequence": "$OPTION_SEQ",
        "active": "$OPTION_ACTIVE",
        "notes": "$OPTION_NOTES_ESCAPED"
    },
    "browser_running": $BROWSER_RUNNING,
    "screenshot_path": "/tmp/task_final_state.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/add_list_option_result.json 2>/dev/null || sudo rm -f /tmp/add_list_option_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_list_option_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_list_option_result.json
chmod 666 /tmp/add_list_option_result.json 2>/dev/null || sudo chmod 666 /tmp/add_list_option_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/add_list_option_result.json"
cat /tmp/add_list_option_result.json
echo ""
echo "=== Export Complete ==="