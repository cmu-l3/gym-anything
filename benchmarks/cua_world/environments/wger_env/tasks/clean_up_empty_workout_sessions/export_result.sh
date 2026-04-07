#!/bin/bash
# export_result.sh — Export result for clean_up_empty_workout_sessions task

echo "=== Exporting clean_up_empty_workout_sessions result ==="
source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load target IDs
EMPTY_IDS=$(cat /tmp/empty_session_ids.txt 2>/dev/null)
VALID_IDS=$(cat /tmp/valid_session_ids.txt 2>/dev/null)

REMAINING_EMPTY=0
REMAINING_VALID=0

TOKEN=$(get_wger_token)

# Count how many of the original empty sessions still exist
IFS=',' read -ra E_ARRAY <<< "$EMPTY_IDS"
for id in "${E_ARRAY[@]}"; do
    if [ -n "$id" ]; then
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "http://localhost/api/v2/workoutsession/${id}/")
        if [ "$STATUS" = "200" ]; then
            REMAINING_EMPTY=$((REMAINING_EMPTY + 1))
        fi
    fi
done

# Count how many of the original valid sessions still exist
IFS=',' read -ra V_ARRAY <<< "$VALID_IDS"
for id in "${V_ARRAY[@]}"; do
    if [ -n "$id" ]; then
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "http://localhost/api/v2/workoutsession/${id}/")
        if [ "$STATUS" = "200" ]; then
            REMAINING_VALID=$((REMAINING_VALID + 1))
        fi
    fi
done

echo "Remaining empty sessions: $REMAINING_EMPTY (Expected: 0)"
echo "Remaining valid sessions: $REMAINING_VALID (Expected: 10)"

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "remaining_empty": $REMAINING_EMPTY,
    "remaining_valid": $REMAINING_VALID,
    "screenshot_exists": true
}
EOF

# Move securely to prevent permission issues
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="