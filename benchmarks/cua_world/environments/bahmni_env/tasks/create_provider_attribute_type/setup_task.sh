#!/bin/bash
set -u

echo "=== Setting up Create Provider Attribute Type Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time (Anti-Gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 2. Ensure Clean State
# Check if the attribute type already exists and delete it if so.
# We use the OpenMRS REST API for this.
echo "Checking for existing 'National Provider Identifier' attribute type..."

EXISTING_ATTR=$(openmrs_api_get "/providerattributetype?q=National+Provider+Identifier&v=default")
EXISTING_UUID=$(echo "$EXISTING_ATTR" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['results'][0]['uuid'] if data.get('results') else '')" 2>/dev/null || true)

if [ -n "$EXISTING_UUID" ]; then
    log "Found existing attribute type (UUID: $EXISTING_UUID). Purging it to ensure clean state..."
    # Purge via REST API
    curl -sk -X DELETE \
        -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/providerattributetype/${EXISTING_UUID}?purge=true" 2>/dev/null
    
    # Verification check
    sleep 2
    CHECK_AGAIN=$(openmrs_api_get "/providerattributetype?q=National+Provider+Identifier&v=default")
    CHECK_UUID=$(echo "$CHECK_AGAIN" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['results'][0]['uuid'] if data.get('results') else '')" 2>/dev/null || true)
    
    if [ -n "$CHECK_UUID" ]; then
        log "WARNING: Failed to purge existing attribute type. Task verification might be affected."
    else
        log "Successfully purged existing attribute type."
    fi
else
    log "No existing attribute type found. Clean state confirmed."
fi

# 3. Start Browser at Bahmni Home
# We intentionally start at Bahmni Home to force the agent to navigate to OpenMRS Admin,
# verifying their knowledge of the system architecture.
if ! start_browser "$BAHMNI_LOGIN_URL" 4; then
    echo "ERROR: Browser failed to start."
    exit 1
fi

# 4. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="