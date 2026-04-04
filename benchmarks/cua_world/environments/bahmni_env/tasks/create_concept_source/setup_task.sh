#!/bin/bash
set -e
echo "=== Setting up Create Concept Source Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Bahmni/OpenMRS readiness
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni did not become ready in time."
    exit 1
fi

# 1. Clean up state: Check if ICD-11 already exists and purge it if possible
echo "Checking for existing ICD-11 concept source..."
EXISTING_SOURCE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/conceptsource?q=ICD-11&v=default" 2>/dev/null)

EXISTING_UUID=$(echo "$EXISTING_SOURCE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['results'][0]['uuid']) if data.get('results') else print('')")

if [ -n "$EXISTING_UUID" ]; then
    echo "Found existing ICD-11 source ($EXISTING_UUID). Attempting to purge..."
    # Purge via REST API
    curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        -X DELETE \
        "${OPENMRS_API_URL}/conceptsource/${EXISTING_UUID}?purge=true" 2>/dev/null || true
    echo "Purge command sent."
    sleep 2
else
    echo "No existing ICD-11 source found. Clean state confirmed."
fi

# 2. Record initial count of concept sources (for anti-gaming verification)
INITIAL_COUNT=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/conceptsource?limit=1" 2>/dev/null \
    | python3 -c "import sys, json; print(json.load(sys.stdin).get('totalCount', 0))" 2>/dev/null || echo "0")

# If totalCount isn't returned by default config, fall back to counting results
if [ "$INITIAL_COUNT" == "0" ] || [ -z "$INITIAL_COUNT" ]; then
     INITIAL_COUNT=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/conceptsource?v=default&limit=100" 2>/dev/null \
    | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")
fi

echo "$INITIAL_COUNT" > /tmp/initial_source_count.txt
echo "Initial concept source count: $INITIAL_COUNT"

# 3. Start Browser at OpenMRS Admin Page
# The utility function handles SSL dismissal and window focus
if ! start_browser "${BAHMNI_BASE_URL}/openmrs/admin" 3; then
    echo "ERROR: Failed to start browser."
    exit 1
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="