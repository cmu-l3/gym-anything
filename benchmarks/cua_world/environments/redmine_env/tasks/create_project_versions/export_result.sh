#!/bin/bash
set -euo pipefail
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Load internal metadata saved during setup
META="/tmp/task_metadata_internal.json"
if [ ! -f "$META" ]; then
  echo "ERROR: Metadata file missing."
  exit 1
fi

API_KEY=$(jq -r '.api_key' "$META")
PROJECT_ID=$(jq -r '.project_identifier' "$META")
ISSUE1_ID=$(jq -r '.issue1_id' "$META")
ISSUE2_ID=$(jq -r '.issue2_id' "$META")
INITIAL_VERSION_COUNT=$(cat /tmp/initial_version_count.txt 2>/dev/null || echo "0")

# 1. Fetch current Versions via API
VERSIONS_JSON=$(curl -s -H "X-Redmine-API-Key: $API_KEY" \
  "$REDMINE_BASE_URL/projects/$PROJECT_ID/versions.json")

# 2. Fetch the two target Issues to check assignments
ISSUE1_JSON=$(curl -s -H "X-Redmine-API-Key: $API_KEY" \
  "$REDMINE_BASE_URL/issues/$ISSUE1_ID.json")
ISSUE2_JSON=$(curl -s -H "X-Redmine-API-Key: $API_KEY" \
  "$REDMINE_BASE_URL/issues/$ISSUE2_ID.json")

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Construct Result JSON
# We combine all API responses into one JSON for the verifier to parse
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "initial_version_count": $INITIAL_VERSION_COUNT,
  "final_versions_data": $VERSIONS_JSON,
  "issue1_data": $ISSUE1_JSON,
  "issue2_data": $ISSUE2_JSON,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"