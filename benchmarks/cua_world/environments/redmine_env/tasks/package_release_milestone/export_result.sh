#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Redmine State via API
# We need to verify: Versions, Wiki Pages, Issues
API_CRED="admin:Admin1234!"
BASE_API="$REDMINE_BASE_URL"
PROJECT_ID="atlantic-horizon"
OUTPUT_FILE="/tmp/task_result.json"

# Fetch data using curl
echo "Fetching final state from Redmine API..."

# Get Versions
VERSIONS_JSON=$(curl -s -u "$API_CRED" "$BASE_API/projects/$PROJECT_ID/versions.json" || echo "{}")

# Get Wiki Pages (List)
WIKI_INDEX_JSON=$(curl -s -u "$API_CRED" "$BASE_API/projects/$PROJECT_ID/wiki/index.json" || echo "{}")

# Get Specific Wiki Page (Permitting_Summary) - check if it exists first
WIKI_PAGE_JSON="{}"
if echo "$WIKI_INDEX_JSON" | grep -q "Permitting_Summary"; then
  WIKI_PAGE_JSON=$(curl -s -u "$API_CRED" "$BASE_API/projects/$PROJECT_ID/wiki/Permitting_Summary.json" || echo "{}")
fi

# Get All Issues for Project (limit 100 to be safe, we have <20)
ISSUES_JSON=$(curl -s -u "$API_CRED" "$BASE_API/issues.json?project_id=$PROJECT_ID&status_id=*&limit=100" || echo "{}")

# Combine into one JSON file
jq -n \
  --argjson versions "$VERSIONS_JSON" \
  --argjson wiki_index "$WIKI_INDEX_JSON" \
  --argjson wiki_page "$WIKI_PAGE_JSON" \
  --argjson issues "$ISSUES_JSON" \
  '{versions: $versions, wiki_index: $wiki_index, wiki_page: $wiki_page, issues: $issues}' \
  > "$OUTPUT_FILE"

# Add timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Update JSON with timestamps
TEMP_JSON=$(mktemp)
jq --arg start "$TASK_START" --arg end "$TASK_END" \
   '. + {task_start: $start, task_end: $end}' "$OUTPUT_FILE" > "$TEMP_JSON"
mv "$TEMP_JSON" "$OUTPUT_FILE"

# Set permissions
chmod 666 "$OUTPUT_FILE"

echo "Result exported to $OUTPUT_FILE"
echo "=== Export complete ==="