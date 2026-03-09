#!/bin/bash
set -e

echo "=== Setting up Create Order Frequency Task ==="

# Source shared Bahmni task utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OpenMRS is reachable
if ! wait_for_bahmni 600; then
    echo "ERROR: OpenMRS is not reachable"
    exit 1
fi

echo "Cleaning up any previous task artifacts..."

# 1. Check for and purge existing '5 Times Daily' Order Frequency
# Fetch all order frequencies
OF_RESP=$(openmrs_api_get "/orderfrequency?v=full")
# Find UUID where concept display name is "5 Times Daily"
EXISTING_OF_UUID=$(echo "$OF_RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
for res in results:
    if res.get('concept', {}).get('display') == '5 Times Daily':
        print(res['uuid'])
        break
")

if [ -n "$EXISTING_OF_UUID" ]; then
    log "Purging existing Order Frequency: $EXISTING_OF_UUID"
    curl -sk -X DELETE \
        -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/orderfrequency/${EXISTING_OF_UUID}?purge=true" || true
fi

# 2. Check for and purge existing '5 Times Daily' Concept
CONCEPT_RESP=$(openmrs_api_get "/concept?q=5+Times+Daily&v=default")
EXISTING_CONCEPT_UUID=$(echo "$CONCEPT_RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
for res in results:
    if res.get('display') == '5 Times Daily':
        print(res['uuid'])
        break
")

if [ -n "$EXISTING_CONCEPT_UUID" ]; then
    log "Purging existing Concept: $EXISTING_CONCEPT_UUID"
    curl -sk -X DELETE \
        -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/concept/${EXISTING_CONCEPT_UUID}?purge=true" || true
fi

# 3. Launch Browser
URL="https://localhost/openmrs/admin"
echo "Starting browser at $URL..."
if ! start_browser "$URL"; then
    echo "ERROR: Browser failed to start"
    exit 1
fi

# Focus browser window
focus_browser

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="