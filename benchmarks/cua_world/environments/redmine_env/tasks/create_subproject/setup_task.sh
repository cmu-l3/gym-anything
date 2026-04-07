#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_subproject task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Redmine is reachable
if ! wait_for_http "$REDMINE_BASE_URL/login" 120; then
  echo "ERROR: Redmine is not reachable"
  exit 1
fi

# 3. Get Parent Project Info from Seed Data
# The seed result is at /home/ga/redmine_seed_result.json (copied by setup_redmine.sh)
SEED_FILE="/home/ga/redmine_seed_result.json"
if [ ! -f "$SEED_FILE" ]; then
  # Fallback location
  SEED_FILE="/tmp/redmine_seed_result.json"
fi

if [ ! -f "$SEED_FILE" ]; then
  echo "ERROR: Seed result file not found."
  exit 1
fi

# Extract admin API key and parent project info
API_KEY=$(jq -r '.admin_api_key' "$SEED_FILE")
PARENT_IDENTIFIER=$(jq -r '.projects[0].identifier' "$SEED_FILE")
PARENT_NAME=$(jq -r '.projects[0].name' "$SEED_FILE")
PARENT_ID=$(jq -r '.projects[0].id' "$SEED_FILE")

if [ -z "$PARENT_IDENTIFIER" ] || [ "$PARENT_IDENTIFIER" = "null" ]; then
  echo "ERROR: No parent project found in seed data"
  exit 1
fi

echo "Parent Project: $PARENT_NAME ($PARENT_IDENTIFIER)"

# Save parent info for verification export later
echo "$PARENT_ID" > /tmp/expected_parent_id.txt
echo "$PARENT_IDENTIFIER" > /tmp/expected_parent_identifier.txt

# 4. Clean State: Ensure target sub-project does NOT exist
TARGET_IDENTIFIER="electrical-interconnection"
CHECK_URL="$REDMINE_BASE_URL/projects/$TARGET_IDENTIFIER.json"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Redmine-API-Key: $API_KEY" "$CHECK_URL" || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
  echo "Target project $TARGET_IDENTIFIER exists. Deleting..."
  curl -s -X DELETE -H "X-Redmine-API-Key: $API_KEY" "$CHECK_URL" > /dev/null
  sleep 2
fi

# 5. Launch Firefox logged in and navigated to the parent project
TARGET_URL="$REDMINE_BASE_URL/projects/$PARENT_IDENTIFIER"
echo "Navigating agent to: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine"
  exit 1
fi

# 6. Final Prep
focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="