#!/bin/bash
set -e
echo "=== Setting up create_encounter_role task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is reachable
wait_for_bahmni 600

# 1. Clean state: Purge 'Scrub Nurse' role if it exists
echo "Checking for existing 'Scrub Nurse' role..."
EXISTING_ROLE=$(openmrs_api_get "/encounterrole?q=Scrub+Nurse&v=default")
ROLE_UUID=$(echo "$EXISTING_ROLE" | python3 -c "import sys, json; data=json.load(sys.stdin); results=data.get('results', []); print(results[0]['uuid'] if results else '')")

if [ -n "$ROLE_UUID" ]; then
    echo "Found existing role ($ROLE_UUID). Purging..."
    # Purge requires DELETE method
    curl -sk -X DELETE \
        -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/encounterrole/${ROLE_UUID}?purge=true" 2>/dev/null || true
    echo "Existing role purged."
fi

# 2. Record initial count for anti-gaming
# Get all roles to count them
INITIAL_DATA=$(openmrs_api_get "/encounterrole?v=default&limit=100")
INITIAL_COUNT=$(echo "$INITIAL_DATA" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))")
echo "$INITIAL_COUNT" > /tmp/initial_role_count.txt
echo "Initial encounter role count: $INITIAL_COUNT"

# 3. Open Browser to OpenMRS Admin Page
ADMIN_URL="${BAHMNI_BASE_URL}/openmrs/admin"
if ! start_browser "$ADMIN_URL" 4; then
    echo "ERROR: Browser failed to start"
    exit 1
fi

# Focus browser
focus_browser
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="