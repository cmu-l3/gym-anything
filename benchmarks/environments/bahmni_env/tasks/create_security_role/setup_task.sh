#!/bin/bash
# Setup for create_security_role task
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_security_role task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Bahmni to be ready
wait_for_bahmni 600

# Function to get role count
get_role_count() {
  curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/role?v=default&limit=1" 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0"
}

# 1. Clean up: Ensure 'Lab Technician' role does not exist
echo "Checking for existing 'Lab Technician' role..."
ROLE_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/role?q=Lab+Technician&v=default" 2>/dev/null \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('results',[]):
    if r['display'].lower() == 'lab technician':
        print(r['uuid'])
        break
" 2>/dev/null || echo "")

if [ -n "$ROLE_UUID" ]; then
  echo "Removing pre-existing role (UUID: $ROLE_UUID)..."
  curl -sk -X DELETE -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/role/${ROLE_UUID}?purge=true" 2>/dev/null || true
  sleep 1
fi

# 2. Record initial role count for anti-gaming verification
INITIAL_ROLE_COUNT=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/role?v=default&limit=1" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")
  
# Note: OpenMRS role API pagination might mask total count, but we only need to know 
# if the specific role we create adds to the system. 
# A better check is 'does the role exist now? No.'
echo "$INITIAL_ROLE_COUNT" > /tmp/initial_role_count.txt
echo "Initial role count check complete."

# 3. Start Browser
# Start at Bahmni home. Agent must navigate to OpenMRS Admin.
if ! start_browser "${BAHMNI_LOGIN_URL}"; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="