#!/bin/bash
echo "=== Setting up Create Location Attribute Type Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 300; then
  echo "ERROR: Bahmni/OpenMRS is not reachable"
  exit 1
fi

# Record initial count of location attribute types for verification
echo "Recording initial location attribute type count..."
INITIAL_DATA=$(openmrs_api_get "/locationattributetype?v=default")
INITIAL_COUNT=$(echo "$INITIAL_DATA" | jq '.results | length' 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_lat_count.txt
echo "Initial count: $INITIAL_COUNT"

# Check if the target attribute type already exists (clean state)
EXISTING_UUID=$(echo "$INITIAL_DATA" | jq -r '.results[] | select(.display | contains("Landline Extension")) | .uuid' 2>/dev/null | head -1)

if [ -n "$EXISTING_UUID" ] && [ "$EXISTING_UUID" != "null" ]; then
  echo "WARNING: Target attribute type already exists ($EXISTING_UUID). Attempting to retire/purge..."
  # Try to purge it to ensure a clean slate
  curl -sk -X DELETE \
    -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/locationattributetype/${EXISTING_UUID}?purge=true" 2>/dev/null || true
  sleep 2
fi

# Start browser at the Bahmni home page (agent needs to navigate to Admin)
# We start at /bahmni/home to force the agent to find the OpenMRS admin link or type the URL
if ! start_browser "$BAHMNI_LOGIN_URL" 3; then
    echo "ERROR: Failed to start browser"
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="