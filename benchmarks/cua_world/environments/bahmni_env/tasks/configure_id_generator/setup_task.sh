#!/bin/bash
set -e

echo "=== Setting up configure_id_generator task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Wait for Bahmni/OpenMRS to be ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni did not become ready in time."
    exit 1
fi

# 3. Create the Prerequisite "Nutrition ID" Identifier Type via REST API
# The agent needs this to exist so they can select it in the dropdown.
echo "Checking/Creating prerequisite 'Nutrition ID' Identifier Type..."

EXISTING_TYPE_COUNT=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/patientidentifiertype?q=Nutrition+ID&v=default" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")

if [ "$EXISTING_TYPE_COUNT" == "0" ]; then
    PAYLOAD='{
        "name": "Nutrition ID",
        "description": "Identifier for the Nutrition Program",
        "required": false
    }'
    curl -sk -X POST \
        -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "${OPENMRS_API_URL}/patientidentifiertype"
    echo "Created 'Nutrition ID' type."
else
    echo "'Nutrition ID' type already exists."
fi

# 4. Clean State: Ensure no existing ID Source conflicts
# We use direct DB queries via Docker to ensure a clean slate
echo "Cleaning up any existing generators with target name..."
docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e \
    "DELETE FROM idgen_seq_id_gen WHERE id IN (SELECT id FROM idgen_identifier_source WHERE name = 'Nutrition ID Sequence');" 2>/dev/null || true
docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e \
    "DELETE FROM idgen_identifier_source WHERE name = 'Nutrition ID Sequence';" 2>/dev/null || true

# 5. Launch Browser at OpenMRS Administration Page
# We start at the admin page to save the agent some navigation time, focusing on the configuration task.
ADMIN_URL="${BAHMNI_BASE_URL}/openmrs/admin"
if ! start_browser "$ADMIN_URL"; then
    echo "ERROR: Failed to start browser."
    exit 1
fi

# 6. Capture Initial State Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="