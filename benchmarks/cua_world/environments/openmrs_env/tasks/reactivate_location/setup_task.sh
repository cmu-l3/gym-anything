#!/bin/bash
# Setup: reactivate_location task
# Ensures "Isolation Ward B" exists and is set to RETIRED status.

set -e
echo "=== Setting up reactivate_location task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Target Location Details
LOC_NAME="Isolation Ward B"
LOC_DESC="Unit for respiratory isolation cases"
# Arbitrary UUID to track this specific resource
LOC_UUID="150141AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

echo "Ensuring location '$LOC_NAME' exists and is RETIRED..."

# Check if location exists via REST API
EXISTING_LOC=$(omrs_get "/location/$LOC_UUID?v=default")

if echo "$EXISTING_LOC" | grep -q "error"; then
    # Location does not exist, create it as retired
    echo "Creating new retired location..."
    
    # payload to create directly (OpenMRS REST might not allow creating as retired directly, 
    # so we create active then retire)
    CREATE_PAYLOAD=$(cat <<EOF
{
  "uuid": "$LOC_UUID",
  "name": "$LOC_NAME",
  "description": "$LOC_DESC"
}
EOF
)
    omrs_post "/location" "$CREATE_PAYLOAD" > /dev/null
    
    # Now retire it
    omrs_delete "/location/$LOC_UUID?reason=Seasonal+Closure" > /dev/null
    echo "Created and retired $LOC_NAME"

else
    # Location exists, ensure it is retired
    IS_RETIRED=$(echo "$EXISTING_LOC" | python3 -c "import sys, json; print(json.load(sys.stdin).get('retired', False))")
    
    if [ "$IS_RETIRED" == "False" ]; then
        echo "Location exists but is active. Retiring now..."
        omrs_delete "/location/$LOC_UUID?reason=Setup+Script+Reset" > /dev/null
    else
        echo "Location already exists and is retired."
    fi
fi

# Verify initial state via DB query to be absolutely sure
echo "Verifying initial DB state..."
INITIAL_STATE=$(omrs_db_query "SELECT retired FROM location WHERE uuid='$LOC_UUID'")
echo "Initial DB Retired State (1=True, 0=False): $INITIAL_STATE"

if [ "$INITIAL_STATE" != "1" ]; then
    echo "WARNING: Failed to set initial state to retired. DB says: $INITIAL_STATE"
    # Try one more force update via DB if API failed
    omrs_db_query "UPDATE location SET retired=1, retire_reason='Force Setup' WHERE uuid='$LOC_UUID'"
fi

# Ensure Firefox is open and logged in (landing on Home)
# We land on Home so the agent has to navigate to Admin > Locations
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="