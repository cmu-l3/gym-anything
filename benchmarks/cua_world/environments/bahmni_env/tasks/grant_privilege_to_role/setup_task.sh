#!/bin/bash
set -e

echo "=== Setting up Grant Privilege task ==="

# Source shared Bahmni task utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is ready
wait_for_bahmni 600

# ------------------------------------------------------------------
# STATE PREPARATION: Ensure "Midwife" role exists WITHOUT "Add Patients"
# ------------------------------------------------------------------
echo "Configuring initial state for role 'Midwife'..."

# Define credentials and URL
AUTH="-u ${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}"
API="${OPENMRS_API_URL}"

# 1. Check if role exists
ROLE_JSON=$(curl -sk $AUTH "${API}/role/Midwife?v=full" 2>/dev/null || echo "{}")
ROLE_EXISTS=$(echo "$ROLE_JSON" | python3 -c "import sys, json; print('true' if json.load(sys.stdin).get('uuid') else 'false')" 2>/dev/null || echo "false")

# 2. If it exists, check if it already has the privilege. If so, or if we want a clean slate, delete it.
# Note: In OpenMRS, modifying a role via REST to *remove* a privilege can be verbose. 
# Deleting and recreating is cleaner for a setup script.
if [ "$ROLE_EXISTS" = "true" ]; then
    echo "Role 'Midwife' exists. Purging to ensure clean state..."
    # 'purge=true' hard deletes the role
    curl -sk -X DELETE $AUTH "${API}/role/Midwife?purge=true" 2>/dev/null || true
    sleep 2
fi

# 3. Create the role fresh (without 'Add Patients')
echo "Creating 'Midwife' role..."
CREATE_PAYLOAD='{
    "name": "Midwife",
    "description": "Midwifery staff responsible for maternity care",
    "privileges": []
}'

# Create role
curl -sk -X POST $AUTH \
    -H "Content-Type: application/json" \
    -d "$CREATE_PAYLOAD" \
    "${API}/role" > /dev/null

# 4. Verify creation
CHECK_JSON=$(curl -sk $AUTH "${API}/role/Midwife?v=full" 2>/dev/null || echo "{}")
HAS_PRIVILEGE=$(echo "$CHECK_JSON" | grep -i "Add Patients" || echo "")

if [ -n "$HAS_PRIVILEGE" ]; then
    echo "CRITICAL ERROR: Created role already has 'Add Patients'. Setup failed."
    exit 1
fi

echo "Role 'Midwife' prepared successfully."

# ------------------------------------------------------------------
# BROWSER SETUP
# ------------------------------------------------------------------
ADMIN_URL="${BAHMNI_BASE_URL}/openmrs/admin"
echo "Launching browser to: $ADMIN_URL"

# Launch browser using shared utility (handles SSL dismissal, focusing)
start_browser "$ADMIN_URL" 4

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="