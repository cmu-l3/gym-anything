#!/bin/bash
set -u

echo "=== Setting up Create Visit Attribute Type Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Clean state: Remove "Arrival Method" if it already exists
echo "Checking for existing 'Arrival Method' attribute type..."
EXISTING=$(openmrs_api_get "/visitattributetype?q=Arrival+Method&v=default")
EXISTING_UUID=$(echo "$EXISTING" | jq -r '.results[0].uuid // empty' 2>/dev/null || true)

if [ -n "$EXISTING_UUID" ]; then
  log "Found existing attribute type (UUID: $EXISTING_UUID). Purging..."
  # Purge the attribute type to ensure a clean slate
  curl -sk -X DELETE \
    -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/visitattributetype/${EXISTING_UUID}?purge=true" 2>/dev/null || true
  sleep 2
else
  log "No existing attribute type found. Clean state confirmed."
fi

# Start Browser at Bahmni Home
# (Agent must log in and navigate to OpenMRS Admin themselves)
if ! start_browser "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="