#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_privilege task ==="

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Verify Bahmni/OpenMRS is running
wait_for_bahmni 300

# Function to check if privilege exists via API
check_privilege_exists() {
    local name="$1"
    # URL encode the name for the API call
    local encoded_name
    encoded_name=$(echo "$name" | sed 's/ /%20/g')
    
    local code
    code=$(curl -sk -o /dev/null -w "%{http_code}" \
        -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/privilege/${encoded_name}" 2>/dev/null || echo "000")
    
    if [ "$code" = "200" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Check if the target privilege already exists (from a previous run)
PRIV_NAME="View Triage Queue"
EXISTS=$(check_privilege_exists "$PRIV_NAME")

echo "Initial check for '$PRIV_NAME': $EXISTS"

# If the privilege already exists, purge it to ensure clean state
if [ "$EXISTS" = "true" ]; then
    echo "Cleaning up pre-existing '$PRIV_NAME' privilege..."
    
    encoded_name=$(echo "$PRIV_NAME" | sed 's/ /%20/g')
    
    curl -skS -X DELETE \
        -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        -H "Content-Type: application/json" \
        "${OPENMRS_API_URL}/privilege/${encoded_name}?purge=true" 2>/dev/null || true
    
    sleep 2
    
    # Verify deletion
    VERIFY_EXISTS=$(check_privilege_exists "$PRIV_NAME")
    if [ "$VERIFY_EXISTS" = "true" ]; then
        echo "WARNING: Failed to delete existing privilege. Task may be compromised."
    else
        echo "Privilege deleted successfully."
    fi
fi

# Record that privilege does not exist at start (for verification)
echo "false" > /tmp/initial_privilege_exists.txt

# Start browser at OpenMRS admin page
# Note: task_utils.sh provides start_browser which handles SSL warnings
start_browser "${BAHMNI_BASE_URL}/openmrs/admin"

# Wait for page load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="