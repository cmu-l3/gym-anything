#!/bin/bash
set -u

echo "=== Setting up Create Care Setting Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni not reachable"
    exit 1
fi

# Clean up: Ensure "Telemedicine" care setting does NOT exist
echo "Checking for existing 'Telemedicine' care setting..."
EXISTING_JSON=$(openmrs_api_get "/caresetting?v=full")
EXISTING_UUID=$(echo "$EXISTING_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
for r in results:
    if r.get('name') == 'Telemedicine':
        print(r.get('uuid'))
        break
")

if [ -n "$EXISTING_UUID" ]; then
    echo "Found existing Telemedicine setting ($EXISTING_UUID). Retiring/Purging..."
    # OpenMRS REST API often supports retiring via DELETE or purging with ?purge=true
    # We'll try to retire it first, then rename it to avoid collision if purge fails
    
    # Retire
    curl -sk -X DELETE -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/caresetting/${EXISTING_UUID}" >/dev/null 2>&1 || true
        
    # Purge (hard delete)
    curl -sk -X DELETE -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/caresetting/${EXISTING_UUID}?purge=true" >/dev/null 2>&1 || true
        
    echo "Cleanup attempted."
fi

# Record initial count of care settings
INITIAL_JSON=$(openmrs_api_get "/caresetting?v=default")
INITIAL_COUNT=$(echo "$INITIAL_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial Care Setting count: $INITIAL_COUNT"

# Launch Browser
echo "Launching browser..."
restart_browser "$BAHMNI_LOGIN_URL" 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="