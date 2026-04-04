#!/bin/bash
set -u

echo "=== Setting up Create Location Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# 1. Clean up: Check if 'Pediatrics Ward' already exists and purge it
echo "Checking for existing 'Pediatrics Ward' location..."
EXISTING_LOC=$(openmrs_api_get "/location?q=Pediatrics+Ward&v=default")
EXISTING_UUID=$(echo "$EXISTING_LOC" | python3 -c "import sys, json; res=json.load(sys.stdin); print(res['results'][0]['uuid']) if res['results'] else print('')")

if [ -n "$EXISTING_UUID" ]; then
  echo "Found existing location (UUID: $EXISTING_UUID). Purging..."
  # Purge the location to ensure a clean slate
  curl -sk -X DELETE \
    -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/location/${EXISTING_UUID}?purge=true" 2>/dev/null || true
  sleep 2
else
  echo "No existing 'Pediatrics Ward' location found. Clean state verified."
fi

# 2. Record initial location count
echo "Recording initial location count..."
INITIAL_COUNT_JSON=$(openmrs_api_get "/location?v=default&limit=100")
INITIAL_COUNT=$(echo "$INITIAL_COUNT_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))")
echo "$INITIAL_COUNT" > /tmp/initial_location_count.txt
echo "Initial location count: $INITIAL_COUNT"

# 3. Start Browser at Bahmni Home (Agent must navigate to /openmrs/admin)
echo "Starting browser..."
if ! start_browser "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="