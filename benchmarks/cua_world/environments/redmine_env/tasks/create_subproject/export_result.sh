#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_subproject results ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Configuration Data
SEED_FILE="/home/ga/redmine_seed_result.json"
[ -f "$SEED_FILE" ] || SEED_FILE="/tmp/redmine_seed_result.json"

if [ -f "$SEED_FILE" ]; then
  API_KEY=$(jq -r '.admin_api_key' "$SEED_FILE")
else
  # Fallback if seed file missing (unlikely)
  API_KEY="admin" 
fi

EXPECTED_PARENT_ID=$(cat /tmp/expected_parent_id.txt 2>/dev/null || echo "")
TARGET_IDENTIFIER="electrical-interconnection"

# 3. Query Redmine API for the result project
# We include enabled_modules and trackers to verify configuration
API_URL="$REDMINE_BASE_URL/projects/$TARGET_IDENTIFIER.json?include=enabled_modules,trackers"
PROJECT_JSON=$(curl -s -H "X-Redmine-API-Key: $API_KEY" "$API_URL" || echo "{}")

# Check if project exists (curl returns the json, check for .project.id)
PROJECT_EXISTS=$(echo "$PROJECT_JSON" | jq -r '.project.id // empty')

# 4. Anti-gaming timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PROJECT_CREATED_ON=$(echo "$PROJECT_JSON" | jq -r '.project.created_on // empty')
# Convert created_on to timestamp if possible, or just rely on existence check
# Since we deleted it in setup, existence implies creation during task.

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "project_found": $(if [ -n "$PROJECT_EXISTS" ]; then echo "true"; else echo "false"; fi),
  "project_data": $PROJECT_JSON,
  "expected_parent_id": "$EXPECTED_PARENT_ID",
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"