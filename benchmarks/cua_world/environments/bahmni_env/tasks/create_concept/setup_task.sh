#!/bin/bash
echo "=== Setting up Create Concept Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Clean state: Check if the concept already exists and try to retire/purge it
# This ensures the agent actually creates it
CONCEPT_NAME="Patient Satisfaction Score"
echo "Checking for existing concept: $CONCEPT_NAME"

# Query API
EXISTING_CONCEPT=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/concept?q=Patient+Satisfaction+Score&v=default")

# Check if any results returned
COUNT=$(echo "$EXISTING_CONCEPT" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")

if [ "$COUNT" -gt "0" ]; then
    echo "Found existing concept(s). Attempting to purge..."
    # Extract UUIDs and purge
    echo "$EXISTING_CONCEPT" | python3 -c "import sys, json; print('\n'.join([r['uuid'] for r in json.load(sys.stdin).get('results', [])]))" | while read -r uuid; do
        if [ -n "$uuid" ]; then
            echo "Purging concept UUID: $uuid"
            curl -sk -X DELETE -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
                "${OPENMRS_API_URL}/concept/$uuid?purge=true" 2>/dev/null || true
        fi
    done
else
    echo "No existing concept found. Clean state confirmed."
fi

# Launch browser to OpenMRS Admin page (NOT Bahmni Home)
# The admin UI is distinctly different
ADMIN_URL="https://localhost/openmrs/admin"

# Kill any existing browser
stop_browser

# Start browser pointing to Admin UI
# Note: start_browser handles SSL warning dismissal
if ! start_browser "$ADMIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

# Focus and maximize
focus_browser || true
maximize_active_window

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="