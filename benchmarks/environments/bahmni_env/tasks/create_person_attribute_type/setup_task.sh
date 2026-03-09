#!/bin/bash
set -e
echo "=== Setting up Create Person Attribute Type Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Clean state: Remove "Preferred Language" attribute type if it already exists
echo "Checking for existing 'Preferred Language' attribute type..."
EXISTING_ATTR=$(openmrs_api_get "/personattributetype?q=Preferred+Language&v=default")
EXISTING_UUID=$(echo "$EXISTING_ATTR" | jq -r '.results[] | select(.display | test("(?i)Preferred Language")) | .uuid' | head -n 1)

if [ -n "$EXISTING_UUID" ] && [ "$EXISTING_UUID" != "null" ]; then
  log "Found existing attribute type (UUID: $EXISTING_UUID). Purging for clean state..."
  # Delete the attribute type
  curl -sk -X DELETE \
    -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/personattributetype/${EXISTING_UUID}?purge=true" 2>/dev/null || true
  sleep 2
else
  log "No existing 'Preferred Language' attribute type found."
fi

# Record initial count of person attribute types
echo "Recording initial Person Attribute Type count..."
INITIAL_JSON=$(openmrs_api_get "/personattributetype?v=default&limit=100")
INITIAL_COUNT=$(echo "$INITIAL_JSON" | jq '.results | length')
echo "$INITIAL_COUNT" > /tmp/initial_pat_count.txt
log "Initial count: $INITIAL_COUNT"

# Start Browser at Bahmni Home (Agent must navigate to Admin)
# We start at Home to test the agent's ability to navigate to the backend
if ! restart_browser "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_browser || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="