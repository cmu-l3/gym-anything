#!/bin/bash
# Setup for create_concept_map_type task
# Sources shared utilities and records initial state for anti-gaming verification.

set -e

TASK_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source shared Bahmni task utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_concept_map_type task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure Bahmni/OpenMRS is ready
wait_for_bahmni 300

# 1. Clean state: Check if ASSOCIATED-WITH already exists and purge it
# This ensures the agent actually creates it and doesn't just find an old one.
echo "Checking for existing 'ASSOCIATED-WITH' map type..."
SEARCH_RESPONSE=$(openmrs_api_get "/conceptmaptype?v=default&limit=100" 2>/dev/null || echo "{}")

EXISTING_UUID=$(echo "$SEARCH_RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    for r in results:
        if r.get('name', '').upper() == 'ASSOCIATED-WITH':
            print(r.get('uuid', ''))
            sys.exit(0)
except Exception:
    pass
" 2>/dev/null || echo "")

if [ -n "$EXISTING_UUID" ]; then
    echo "Found existing map type (UUID: $EXISTING_UUID). Purging for clean state..."
    # Purge (permanently delete) the map type
    curl -skS -X DELETE \
        -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/conceptmaptype/${EXISTING_UUID}?purge=true" 2>/dev/null || true
    sleep 2
else
    echo "No existing map type found. Clean state verified."
fi

# 2. Record initial count (for anti-gaming: did count increase?)
INITIAL_RESPONSE=$(openmrs_api_get "/conceptmaptype?v=default&limit=100" 2>/dev/null || echo "{}")
INITIAL_COUNT=$(echo "$INITIAL_RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(len(data.get('results', [])))
except:
    print('0')
" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial concept map type count: $INITIAL_COUNT"

# 3. Launch Browser
# We launch to the home page, but agent needs to navigate to OpenMRS Admin
stop_browser
sleep 1
start_browser "${BAHMNI_LOGIN_URL}"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="