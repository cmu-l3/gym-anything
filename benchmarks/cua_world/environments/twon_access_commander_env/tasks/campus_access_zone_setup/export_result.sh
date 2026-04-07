#!/bin/bash
set -e
echo "=== Exporting campus_access_zone_setup result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check text file creation
FILE_PATH="/home/ga/Documents/zones_configured.txt"
FILE_EXISTS="false"
FILE_MTIME="0"
FILE_CONTENT=""

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    # Grab up to 15 lines of content to check
    FILE_CONTENT=$(head -n 15 "$FILE_PATH" 2>/dev/null)
fi

# 2. Check API state
echo "Querying Access Commander API for current zones..."
ac_login
ZONES_JSON=$(ac_api GET "/zones" 2>/dev/null || echo "[]")

# Validate JSON; if API fails or returns HTML, fallback to empty array
if ! echo "$ZONES_JSON" | jq -e . >/dev/null 2>&1; then
    echo "Warning: API did not return valid JSON for /zones. Using empty array."
    ZONES_JSON="[]"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png ga

# 4. Compile JSON result
TEMP_JSON=$(mktemp)
jq -n \
  --arg start "$TASK_START" \
  --arg end "$TASK_END" \
  --arg file_exists "$FILE_EXISTS" \
  --arg mtime "$FILE_MTIME" \
  --arg content "$FILE_CONTENT" \
  --argjson zones "$ZONES_JSON" \
  '{
     task_start: ($start|tonumber),
     task_end: ($end|tonumber),
     file_exists: ($file_exists == "true"),
     file_mtime: ($mtime|tonumber),
     file_content: $content,
     zones: $zones
   }' > "$TEMP_JSON"

# Move safely to /tmp
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="