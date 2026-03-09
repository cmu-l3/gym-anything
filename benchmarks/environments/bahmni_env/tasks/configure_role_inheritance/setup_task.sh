#!/bin/bash
set -e

echo "=== Setting up configure_role_inheritance task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 600; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# define API variables
API_URL="${OPENMRS_API_URL}/role"
AUTH="-u ${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}"
JSON_HEADER="-H Content-Type:application/json"

echo "Ensuring 'Provider' role exists..."
# Check if Provider exists (it's a standard role, usually exists)
PROVIDER_CHECK=$(curl -sk $AUTH "${API_URL}/Provider" || echo "")
if echo "$PROVIDER_CHECK" | grep -q "Object with given uuid doesn't exist"; then
    echo "Creating Provider role..."
    curl -sk $AUTH -X POST $JSON_HEADER -d '{"name":"Provider","description":"Provider role"}' "${API_URL}" > /dev/null
fi

echo "Resetting 'Trainee' role state..."
# Check if Trainee exists
TRAINEE_CHECK=$(curl -sk $AUTH "${API_URL}/Trainee" || echo "")

if echo "$TRAINEE_CHECK" | grep -q "uuid"; then
    # If it exists, we need to clear its inheritance to ensure a clean start
    # We can't easily PATCH to remove specific items in OpenMRS REST without fetching uuid, 
    # so we delete and recreate to be safe and clean.
    echo "Deleting existing Trainee role..."
    # Get UUID
    TRAINEE_UUID=$(echo "$TRAINEE_CHECK" | python3 -c "import sys, json; print(json.load(sys.stdin)['uuid'])")
    curl -sk $AUTH -X DELETE "${API_URL}/${TRAINEE_UUID}?purge=true" > /dev/null
    sleep 1
fi

echo "Creating clean 'Trainee' role..."
# Create Trainee role with NO inheritance and NO privileges
curl -sk $AUTH -X POST $JSON_HEADER \
    -d '{"name":"Trainee","description":"Medical student trainee role"}' \
    "${API_URL}" > /dev/null

# Verify setup
FINAL_CHECK=$(curl -sk $AUTH "${API_URL}/Trainee?v=full")
INHERITED_COUNT=$(echo "$FINAL_CHECK" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('inheritedRoles', [])))" 2>/dev/null || echo "0")

if [ "$INHERITED_COUNT" -ne "0" ]; then
    echo "WARNING: Trainee role created but has inherited roles unexpectedly."
else
    echo "Trainee role ready (clean state)."
fi

# Start Browser
echo "Starting browser..."
if ! start_browser "${BAHMNI_LOGIN_URL}" 4; then
    echo "ERROR: Failed to start browser"
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="