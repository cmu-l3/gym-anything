#!/bin/bash
set -e
echo "=== Setting up create_provider task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Wait for OpenMRS to be ready
if ! wait_for_bahmni 600; then
    echo "ERROR: OpenMRS not reachable"
    exit 1
fi

# 3. Clean up any pre-existing provider with the target identifier
# This ensures the agent must actually create it, not just find an old one.
TARGET_ID="DOC-2024-0047"
echo "Checking for existing provider with identifier $TARGET_ID..."

# Fetch all providers (this might be large, but usually fine in test env)
# We use python to filter robustly
EXISTING_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/provider?v=default&limit=100" | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for res in data.get('results', []):
        if res.get('identifier') == '$TARGET_ID':
            print(res['uuid'])
            break
except:
    pass
")

if [ -n "$EXISTING_UUID" ]; then
    echo "Removing pre-existing provider ($EXISTING_UUID)..."
    curl -sk -X DELETE -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/provider/${EXISTING_UUID}?purge=true"
    echo "Cleanup complete."
else
    echo "No pre-existing provider found."
fi

# 4. Record initial provider count
INITIAL_COUNT=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/provider?v=default&limit=100" | \
    python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_provider_count.txt

# 5. Launch Browser pointing to OpenMRS Admin
# We use the raw OpenMRS URL, not the Bahmni app URL
start_browser "${BAHMNI_BASE_URL}/openmrs" 4

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="