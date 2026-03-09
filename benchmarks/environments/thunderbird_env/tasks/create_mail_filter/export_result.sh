#!/bin/bash
echo "=== Exporting create_mail_filter result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/thunderbird_final.png

# ============================================================
# Check message filter rules file
# ============================================================
MSGFILTER_FILE="${THUNDERBIRD_PROFILE}/Mail/Local Folders/msgFilterRules.dat"
INITIAL_FILTERS=$(cat /tmp/initial_filter_count 2>/dev/null || echo "0")

FILTER_CREATED="false"
CURRENT_FILTER_COUNT=0
FILTER_NAME=""
FILTER_CONDITION=""
FILTER_ACTION=""
FILTER_TARGET=""
FILTER_FILE_CONTENT=""

if [ -f "$MSGFILTER_FILE" ]; then
    CURRENT_FILTER_COUNT=$(grep -c "^name=" "$MSGFILTER_FILE" 2>/dev/null || echo "0")
    FILTER_FILE_CONTENT=$(cat "$MSGFILTER_FILE" 2>/dev/null || echo "")

    if [ "$CURRENT_FILTER_COUNT" -gt "$INITIAL_FILTERS" ]; then
        FILTER_CREATED="true"

        # Extract the last filter's details
        # msgFilterRules.dat format:
        # name="Filter Name"
        # enabled="yes"
        # type="17"
        # action="Move to folder"
        # actionValue="mailbox://nobody@Local Folders/Urgent"
        # condition="AND (subject,contains,urgent)"

        FILTER_NAME=$(grep "^name=" "$MSGFILTER_FILE" | tail -1 | sed 's/^name="//' | sed 's/"$//' | tr -d '\r')
        FILTER_CONDITION=$(grep "^condition=" "$MSGFILTER_FILE" | tail -1 | sed 's/^condition="//' | sed 's/"$//' | tr -d '\r')
        FILTER_ACTION=$(grep "^action=" "$MSGFILTER_FILE" | tail -1 | sed 's/^action="//' | sed 's/"$//' | tr -d '\r')
        FILTER_TARGET=$(grep "^actionValue=" "$MSGFILTER_FILE" | tail -1 | sed 's/^actionValue="//' | sed 's/"$//' | tr -d '\r')
    fi
fi

# Check if "Urgent" folder was created
URGENT_FOLDER_EXISTS="false"
if folder_exists "Urgent"; then
    URGENT_FOLDER_EXISTS="true"
fi
# Also check in .sbd directories
if [ -d "${LOCAL_MAIL_DIR}/Local Folders.sbd" ] && [ -f "${LOCAL_MAIL_DIR}/Local Folders.sbd/Urgent" ]; then
    URGENT_FOLDER_EXISTS="true"
fi

# Check Thunderbird is still running
TB_RUNNING="false"
if is_thunderbird_running; then
    TB_RUNNING="true"
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape JSON values (strip only outer quotes from json.dumps output)
FILTER_NAME_ESC=$(echo "$FILTER_NAME" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$FILTER_NAME")
FILTER_CONDITION_ESC=$(echo "$FILTER_CONDITION" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$FILTER_CONDITION")
FILTER_ACTION_ESC=$(echo "$FILTER_ACTION" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$FILTER_ACTION")
FILTER_TARGET_ESC=$(echo "$FILTER_TARGET" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$FILTER_TARGET")

cat > "$TEMP_JSON" << EOF
{
    "filter_created": $FILTER_CREATED,
    "initial_filter_count": $INITIAL_FILTERS,
    "current_filter_count": $CURRENT_FILTER_COUNT,
    "filter_name": "$FILTER_NAME_ESC",
    "filter_condition": "$FILTER_CONDITION_ESC",
    "filter_action": "$FILTER_ACTION_ESC",
    "filter_target": "$FILTER_TARGET_ESC",
    "urgent_folder_exists": $URGENT_FOLDER_EXISTS,
    "thunderbird_running": $TB_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
