#!/bin/bash
set -u

echo "=== Setting up Retire Location Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 2. Wait for OpenMRS/Bahmni to be ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni did not become ready in time."
    exit 1
fi

# 3. Create the Target Location via REST API
# We verify if it exists first. If it does, we unretire it to ensure clean state.
echo "Preparing location 'Satellite Clinic East'..."

# Search for existing location
SEARCH_RES=$(openmrs_api_get "/location?q=Satellite+Clinic+East&v=full&includeAll=true")
EXISTING_UUID=$(echo "$SEARCH_RES" | python3 -c "import json,sys; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r['results'] else '')" 2>/dev/null)

if [ -n "$EXISTING_UUID" ]; then
    echo "Location exists ($EXISTING_UUID). Ensuring it is active (not retired)..."
    # Unretire it by sending retired=false
    openmrs_api_post "/location/$EXISTING_UUID" '{"retired": false, "retireReason": ""}' > /dev/null
    LOCATION_UUID="$EXISTING_UUID"
else
    echo "Creating new location..."
    PAYLOAD='{
        "name": "Satellite Clinic East",
        "description": "Temporary outreach clinic for the Eastern District community health drive",
        "address1": "45 Riverside Drive",
        "cityVillage": "Riverside",
        "stateProvince": "Central",
        "country": "Demo Country",
        "postalCode": "10200"
    }'
    CREATE_RES=$(openmrs_api_post "/location" "$PAYLOAD")
    LOCATION_UUID=$(echo "$CREATE_RES" | python3 -c "import json,sys; print(json.load(sys.stdin).get('uuid',''))" 2>/dev/null)
fi

if [ -z "$LOCATION_UUID" ]; then
    echo "ERROR: Failed to create or retrieve location UUID."
    exit 1
fi

# Save UUID for export script
echo "$LOCATION_UUID" > /tmp/target_location_uuid.txt
echo "Target Location UUID: $LOCATION_UUID"

# 4. Record Initial State (verify it is NOT retired)
INITIAL_STATE=$(openmrs_api_get "/location/$LOCATION_UUID")
IS_RETIRED=$(echo "$INITIAL_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('retired', False))" 2>/dev/null)
echo "$IS_RETIRED" > /tmp/initial_retired_state.txt
echo "Initial Retired State: $IS_RETIRED"

# 5. Launch Browser
# Start at Bahmni Home. Agent needs to figure out to go to OpenMRS Admin.
start_browser "${BAHMNI_BASE_URL}/bahmni/home"

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="