#!/bin/bash
echo "=== Exporting credential_leak_response task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/task_initial_count.txt 2>/dev/null || echo "25")

# Authenticate to the API
ac_login

# Fetch the summary of all users
USERS_SUMMARY=$(ac_api GET "/users?limit=1000" 2>/dev/null || echo "[]")

# Fetch full details for every user to ensure we capture nested card objects
TEMP_USERS=$(mktemp)
echo "[" > "$TEMP_USERS"
USER_IDS=$(echo "$USERS_SUMMARY" | jq -r '.[].id' 2>/dev/null || echo "")
FIRST="true"

for id in $USER_IDS; do
    if [ -z "$id" ]; then continue; fi
    USER_DETAIL=$(ac_api GET "/users/$id" 2>/dev/null || echo "{}")
    
    if [ "$FIRST" = "true" ]; then
        echo "$USER_DETAIL" >> "$TEMP_USERS"
        FIRST="false"
    else
        echo ",$USER_DETAIL" >> "$TEMP_USERS"
    fi
done
echo "]" >> "$TEMP_USERS"

# Check for the requested incident report
REPORT_PATH="/home/ga/Documents/compromised_users_report.txt"
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Safely capture the first 5KB of the report, stripping problematic control characters
    REPORT_CONTENT=$(head -c 5000 "$REPORT_PATH" | tr -d '\000-\011\013-\037')
fi

# Capture final screenshot
take_screenshot /tmp/task_end.png

# Safely construct the final JSON result using jq
jq -n \
    --argjson start "$TASK_START" \
    --argjson end "$TASK_END" \
    --argjson initial "$INITIAL_COUNT" \
    --arg exists "$REPORT_EXISTS" \
    --arg created "$REPORT_CREATED_DURING_TASK" \
    --arg content "$REPORT_CONTENT" \
    --slurpfile users "$TEMP_USERS" \
    '{
        task_start: $start,
        task_end: $end,
        initial_count: $initial,
        report_exists: ($exists == "true"),
        report_created_during_task: ($created == "true"),
        report_content: $content,
        users: $users[0]
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json
rm -f "$TEMP_USERS"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="