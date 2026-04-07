#!/bin/bash
set -euo pipefail

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch live ground truth directly from API (most accurate truth state)
LOGIN_JSON=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"$ROCKETCHAT_TASK_USERNAME\",\"password\":\"$ROCKETCHAT_TASK_PASSWORD\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_JSON" | jq -r '.data.userId // empty' 2>/dev/null || true)

API_ROLES="[]"
if [ -n "$TOKEN" ] && [ -n "$USER_ID" ]; then
  PERMS_JSON=$(curl -sS \
    -H "X-Auth-Token: $TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/permissions.list" 2>/dev/null || true)
  
  API_ROLES=$(echo "$PERMS_JSON" | jq -c '[.update[] | select(._id == "mention-all") | .roles[]]' 2>/dev/null || echo "[]")
fi

# Check agent output file
OUTPUT_PATH="/home/ga/mention_all_audit.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read the text safely
    OUTPUT_CONTENT=$(cat "$OUTPUT_PATH" | head -n 20)
fi

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Encode text string to prevent JSON breaking due to newlines
OUTPUT_CONTENT_JSON=$(jq -n --arg content "$OUTPUT_CONTENT" '$content')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_content": $OUTPUT_CONTENT_JSON,
    "ground_truth_roles": $API_ROLES,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Resolve permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="