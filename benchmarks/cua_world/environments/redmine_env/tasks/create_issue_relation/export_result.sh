#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_issue_relation results ==="

TASK_DATA="/tmp/task_relation_data.json"
RESULT_FILE="/tmp/task_result.json"

# Check if task data file exists
if [ ! -f "$TASK_DATA" ]; then
  echo "ERROR: Task data file not found at $TASK_DATA"
  # Create empty result to prevent total failure
  echo "{}" > "$RESULT_FILE"
  exit 0
fi

API_KEY=$(jq -r '.api_key' "$TASK_DATA")
ISSUE_A_ID=$(jq -r '.issue_a_id' "$TASK_DATA")
ISSUE_B_ID=$(jq -r '.issue_b_id' "$TASK_DATA")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Checking relations for Issue #$ISSUE_A_ID and #$ISSUE_B_ID..."

# Fetch relations for Issue A
# We use || echo to handle cases where curl fails (though set -e might catch it first)
RELATIONS_A_JSON=$(curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/issues/$ISSUE_A_ID/relations.json" || echo '{"relations": []}')

# Fetch relations for Issue B (redundancy/verification from other side)
RELATIONS_B_JSON=$(curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/issues/$ISSUE_B_ID/relations.json" || echo '{"relations": []}')

# Take final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# Create JSON result file
# We explicitly construct the JSON to ensure it's valid and contains all needed fields
jq -n \
  --argjson rel_a "$RELATIONS_A_JSON" \
  --argjson rel_b "$RELATIONS_B_JSON" \
  --arg start_time "$TASK_START" \
  --arg issue_a "$ISSUE_A_ID" \
  --arg issue_b "$ISSUE_B_ID" \
  --arg screenshot "$SCREENSHOT_EXISTS" \
  '{
    relations_a: $rel_a,
    relations_b: $rel_b,
    task_start_time: $start_time,
    issue_a_id: $issue_a,
    issue_b_id: $issue_b,
    screenshot_exists: $screenshot
  }' > "$RESULT_FILE"

chmod 666 "$RESULT_FILE"
echo "Result exported to $RESULT_FILE"