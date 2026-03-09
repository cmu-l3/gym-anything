#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_visit_type task ==="

# Record task start time (epoch seconds)
date +%s > /tmp/task_start_time.txt

# Wait for Bahmni/OpenMRS to be ready
wait_for_bahmni 600

# 1. Clean State: Ensure "Telehealth Consultation" does not exist
echo "Checking for existing 'Telehealth Consultation' visit type..."
EXISTING_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/visittype?v=default" | \
  python3 -c "import sys, json; \
  data = json.load(sys.stdin); \
  matches = [r['uuid'] for r in data.get('results', []) if r.get('display', '').strip() == 'Telehealth Consultation']; \
  print(matches[0] if matches else '')")

if [ -n "$EXISTING_UUID" ]; then
    echo "Found existing visit type (UUID: $EXISTING_UUID). Purging..."
    # Purge removes it completely from DB
    curl -sk -X DELETE -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
      "${OPENMRS_API_URL}/visittype/${EXISTING_UUID}?purge=true"
    sleep 2
else
    echo "Clean state verified: 'Telehealth Consultation' does not exist."
fi

# 2. Record initial count of visit types
INITIAL_COUNT=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/visittype?v=default" | \
  python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))")
echo "$INITIAL_COUNT" > /tmp/initial_visit_type_count.txt
echo "Initial visit type count: $INITIAL_COUNT"

# 3. Start Browser at Bahmni Home (Agent must navigate to OpenMRS Admin)
# We start at the standard home page to force the agent to navigate to the admin URL provided in instructions.
if ! start_browser "${BAHMNI_LOGIN_URL}" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

# 4. Capture Initial State Evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="