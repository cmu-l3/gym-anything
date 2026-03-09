#!/bin/bash
set -e
echo "=== Setting up create_form task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming (creation timestamp check)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Ensure Bahmni/OpenMRS is ready
wait_for_bahmni 600

# 3. Clean up any pre-existing form with the target name to ensure a clean slate
#    We use the OpenMRS REST API to find and purge the form.
TARGET_FORM="COVID-19 Screening Form"
echo "Checking for pre-existing form: '$TARGET_FORM'..."

# URL encode the query
ENCODED_QUERY=$(echo "$TARGET_FORM" | sed 's/ /%20/g')

EXISTING_FORMS=$(curl -sk \
  -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/form?v=default&q=${ENCODED_QUERY}" 2>/dev/null || echo '{"results":[]}')

# Parse results and delete matches
echo "$EXISTING_FORMS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for form in data.get('results', []):
    if form.get('name') == '$TARGET_FORM':
        print(form.get('uuid', ''))
" 2>/dev/null | while read -r uuid; do
  if [ -n "$uuid" ]; then
    echo "Purging pre-existing form: $uuid"
    curl -sk -X DELETE \
      -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
      "${OPENMRS_API_URL}/form/${uuid}?purge=true" 2>/dev/null || true
  fi
done

# 4. Record initial form count for comparison
INITIAL_FORM_COUNT=$(curl -sk \
  -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/form?v=default&limit=1" 2>/dev/null \
  | python3 -c "import json,sys; data=json.load(sys.stdin); print(len(data.get('results',[])))" 2>/dev/null || echo "0")
# Note: The API doesn't give a total count easily without iterating, but we rely on the specific form lookup.
# We'll just store a marker that setup is done.
echo "Setup complete" > /tmp/setup_done.txt

# 5. Launch browser at Bahmni home page
#    Agent must navigate to OpenMRS Admin from here or via URL
start_browser "${BAHMNI_BASE_URL}/bahmni/home" 4

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved"

echo "=== create_form task setup complete ==="