#!/bin/bash
echo "=== Exporting enroll_license_plates_lpr result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot as visual evidence
take_screenshot /tmp/task_final.png

# Fetch the updated user records via the AC REST API
ac_login
ac_api GET "/users" > /tmp/all_users.json

# Locate the specific users
KWAME_ID=$(cat /tmp/all_users.json | jq -r '.[] | select(.firstName=="Kwame" and .lastName=="Asante") | .id' 2>/dev/null || echo "")
MEI_ID=$(cat /tmp/all_users.json | jq -r '.[] | select(.firstName=="Mei-Ling" and .lastName=="Zhang") | .id' 2>/dev/null || echo "")

KWAME_JSON="{}"
if [ -n "$KWAME_ID" ] && [ "$KWAME_ID" != "null" ]; then
    ac_api GET "/users/$KWAME_ID" > /tmp/kwame.json
    KWAME_JSON=$(cat /tmp/kwame.json 2>/dev/null || echo "{}")
fi

MEI_JSON="{}"
if [ -n "$MEI_ID" ] && [ "$MEI_ID" != "null" ]; then
    ac_api GET "/users/$MEI_ID" > /tmp/mei.json
    MEI_JSON=$(cat /tmp/mei.json 2>/dev/null || echo "{}")
fi

# Create structured JSON result payload for the Python verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "kwame_id": "$KWAME_ID",
    "mei_id": "$MEI_ID",
    "kwame_data": $KWAME_JSON,
    "mei_data": $MEI_JSON
}
EOF

# Safely copy to the export location using sudo in case of permission clashes
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="