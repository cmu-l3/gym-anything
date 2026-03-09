#!/bin/bash
set -u

echo "=== Setting up Create Encounter Type Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming (timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# 3. Clean State: Remove "Telehealth Consultation" if it already exists
# This prevents the agent from getting credit for a pre-existing state
echo "Checking for existing 'Telehealth Consultation' encounter type..."
EXISTING=$(openmrs_api_get "/encountertype?q=Telehealth+Consultation&v=default")
EXISTING_UUID=$(echo "$EXISTING" | jq -r '.results[] | select(.display == "Telehealth Consultation") | .uuid' 2>/dev/null | head -1)

if [ -n "$EXISTING_UUID" ] && [ "$EXISTING_UUID" != "null" ]; then
  echo "Found existing encounter type (UUID: $EXISTING_UUID). Attempting to purge..."
  # Purge the encounter type. Note: This will fail if encounters of this type exist, 
  # but in a fresh task env, they shouldn't.
  curl -sk -X DELETE \
    -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/encountertype/${EXISTING_UUID}?purge=true" 2>/dev/null || true
  sleep 2
else
  echo "No existing 'Telehealth Consultation' found. Clean state verified."
fi

# 4. Record initial list of encounter types (Anti-gaming snapshot)
echo "Recording initial encounter types..."
openmrs_api_get "/encountertype?v=default&limit=100" > /tmp/initial_encounter_types.json

# 5. Launch Browser
# Start at Bahmni Home, forcing the agent to navigate to OpenMRS Admin
echo "Launching browser..."
if ! start_browser "${BAHMNI_LOGIN_URL}" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

# 6. Capture initial state evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="