#!/bin/bash
set -u

echo "=== Setting up Create Relationship Type task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp.txt

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Clean up: Check if the relationship type already exists and delete it if so
# We search for "Community Health Worker" or "Client"
EXISTING_TYPES=$(openmrs_api_get "/relationshiptype?v=default")

# Parse JSON to find UUIDs of conflicting types (using python for reliability)
UUIDS_TO_DELETE=$(echo "$EXISTING_TYPES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
for r in results:
    display = r.get('display', '').lower()
    if 'community health worker' in display or 'client' in display:
        print(r['uuid'])
")

if [ -n "$UUIDS_TO_DELETE" ]; then
    echo "Found existing conflicting relationship types. Cleaning up..."
    for uuid in $UUIDS_TO_DELETE; do
        echo "Deleting relationship type: $uuid"
        # Purge to remove completely
        curl -skS -X DELETE \
            -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
            "${OPENMRS_API_URL}/relationshiptype/${uuid}?purge=true" 2>/dev/null || true
    done
fi

# Record initial count of relationship types
INITIAL_JSON=$(openmrs_api_get "/relationshiptype?v=default")
INITIAL_COUNT=$(echo "$INITIAL_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial relationship type count: $INITIAL_COUNT"

# Start Browser at OpenMRS Admin page (direct navigation as requested)
TARGET_URL="${OPENMRS_BASE_URL}/admin"
if ! start_browser "$TARGET_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_browser || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="