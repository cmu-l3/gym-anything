#!/bin/bash
echo "=== Setting up create_drug task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")" > /tmp/task_start_iso.txt

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 300; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

echo "Cleaning up any existing target drug..."
# Search for existing drug to ensure clean state
# Using curl directly because we need specific filtering
EXISTING_DRUGS=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/drug?q=Amoxicillin&v=default")

# Parse JSON to find exact match on name "Amoxicillin 500mg Capsule"
EXISTING_UUID=$(echo "$EXISTING_DRUGS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for result in data.get('results', []):
        if result.get('display', '').lower() == 'amoxicillin 500mg capsule':
            print(result.get('uuid'))
            break
except:
    pass
")

if [ -n "$EXISTING_UUID" ]; then
    echo "Found existing drug ($EXISTING_UUID), purging..."
    curl -sk -X DELETE -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/drug/${EXISTING_UUID}?purge=true"
    sleep 2
else
    echo "No existing drug found (clean state)."
fi

# Record initial drug count for verification
INITIAL_COUNT=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "SELECT COUNT(*) FROM drug WHERE retired = 0" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_drug_count.txt

# Start Browser at Bahmni Login
if ! start_browser "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="