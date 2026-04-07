#!/bin/bash
# Export script for update_user_properties task
# Fetches the final state of user jsmith from the API and saves to JSON

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ---------------------------------------------------------------------------
# Fetch Final User State
# ---------------------------------------------------------------------------
# We fetch the user 'jsmith' from the API to verify properties
echo "Fetching final user state..."
USER_JSON=$(curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" "$NUXEO_URL/api/v1/user/jsmith")

# Check if user exists (curl might return 404 HTML or error JSON)
USER_EXISTS="false"
if echo "$USER_JSON" | grep -q "\"entity-type\":\"user\""; then
    USER_EXISTS="true"
fi

# ---------------------------------------------------------------------------
# Prepare Result JSON
# ---------------------------------------------------------------------------
# We save the raw API response embedded in our result JSON for the python verifier to parse.
# We also include timestamps and existence checks.

# Create a safe temporary file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use jq to construct the JSON if available, otherwise manual construction
if command -v jq >/dev/null; then
    jq -n \
      --argjson user_data "$USER_JSON" \
      --arg exists "$USER_EXISTS" \
      --arg start "$TASK_START" \
      --arg end "$TASK_END" \
      '{
        user_data: $user_data,
        user_exists: ($exists == "true"),
        task_start: $start,
        task_end: $end
      }' > "$TEMP_JSON"
else
    # Fallback to python for JSON construction to avoid string escaping issues
    python3 -c "
import json
import sys

try:
    user_data = json.loads('$USER_JSON')
except:
    user_data = {}

result = {
    'user_data': user_data,
    'user_exists': '$USER_EXISTS' == 'true',
    'task_start': $TASK_START,
    'task_end': $TASK_END
}
print(json.dumps(result))
" > "$TEMP_JSON"
fi

# Move to standard location with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="