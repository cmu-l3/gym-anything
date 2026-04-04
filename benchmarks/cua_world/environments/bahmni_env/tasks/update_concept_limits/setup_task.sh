#!/bin/bash
set -u

echo "=== Setting up update_concept_limits task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Concept UUID for "Weight (kg)"
CONCEPT_UUID="5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

# Wait for OpenMRS to be ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni/OpenMRS is not reachable"
    exit 1
fi

echo "Resetting concept limits to ensure clean state..."

# We must reset the concept so the agent actually has work to do.
# We set all limits to null via the REST API.
RESET_PAYLOAD='{
  "lowAbsolute": null,
  "lowCritical": null,
  "hiCritical": null,
  "hiAbsolute": null
}'

# Note: The 'openmrs_api_post' function in task_utils.sh is for POST.
# We need strictly a POST to /concept/{uuid} to update it (OpenMRS 2.x REST behavior for updates varies, 
# but often POST to the resource URI updates it).
# Let's use curl directly to be precise with the URL and Method.

HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
  -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d "$RESET_PAYLOAD" \
  "${OPENMRS_API_URL}/concept/${CONCEPT_UUID}")

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo "WARNING: Failed to reset concept limits (HTTP $HTTP_CODE). Task may be pre-completed."
else
    echo "Concept limits reset successfully."
fi

# Verify reset state
CURRENT_STATE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/concept/${CONCEPT_UUID}")
echo "Current concept state (snippet):"
echo "$CURRENT_STATE" | grep -E "hiAbsolute|lowAbsolute" || true

# Start Browser at Bahmni Home
# The agent must figure out how to get to OpenMRS Admin (or know the URL)
# We start them at the standard Bahmni login.
if ! start_browser "$BAHMNI_LOGIN_URL" 4; then
    echo "ERROR: Browser failed to start"
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="