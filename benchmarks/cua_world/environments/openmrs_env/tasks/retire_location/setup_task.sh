#!/bin/bash
# Setup: retire_location task
# Ensures 'Temporary Fever Clinic' exists and is ACTIVE (not retired).

echo "=== Setting up retire_location task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_iso.txt
date +%s > /tmp/task_start_timestamp

LOCATION_NAME="Temporary Fever Clinic"

echo "Checking status of '$LOCATION_NAME'..."

# 1. Search for the location
SEARCH_RESULT=$(omrs_get "/location?q=$(echo "$LOCATION_NAME" | sed 's/ /%20/g')&v=full")
LOCATION_UUID=$(echo "$SEARCH_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
# Filter for exact name match to avoid partials
target = next((r for r in results if r['name'] == '$LOCATION_NAME'), None)
if target:
    print(target['uuid'])
" 2>/dev/null)

# 2. Create or Reset the location
if [ -z "$LOCATION_UUID" ]; then
    echo "Location not found. Creating new location..."
    # Need a parent location (usually 'Unknown Location' or similar for root, or just null)
    # We'll try to find a valid parent UUID just in case, or omit if not strict
    PARENT_UUID="6351fcf4-e311-4a19-90f9-35667d99a8af" # Common demo data root
    
    CREATE_PAYLOAD=$(cat <<EOF
{
  "name": "$LOCATION_NAME",
  "description": "Seasonal overflow clinic",
  "parentLocation": "$PARENT_UUID"
}
EOF
)
    CREATE_RESP=$(omrs_post "/location" "$CREATE_PAYLOAD")
    LOCATION_UUID=$(echo "$CREATE_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uuid', ''))")
    
    if [ -z "$LOCATION_UUID" ]; then
        echo "ERROR: Failed to create location."
        exit 1
    fi
    echo "Created location: $LOCATION_UUID"

else
    echo "Location found ($LOCATION_UUID). Checking if retired..."
    # Check if it is already retired
    IS_RETIRED=$(echo "$SEARCH_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
target = next((r for r in results if r['name'] == '$LOCATION_NAME'), {})
print('true' if target.get('retired') else 'false')
")

    if [ "$IS_RETIRED" == "true" ]; then
        echo "Location is currently retired. Un-retiring it..."
        # Un-retire by setting retired=false and clearing the reason
        omrs_post "/location/$LOCATION_UUID" '{"retired": false, "retireReason": null}' > /dev/null
        echo "Location un-retired."
    else
        echo "Location is already active."
    fi
fi

# Save UUID for export script
echo "$LOCATION_UUID" > /tmp/target_location_uuid.txt

# 3. Launch Browser
# Start at the Home page (Administrator Dashboard)
HOME_URL="http://localhost/openmrs/spa/home"
ensure_openmrs_logged_in "$HOME_URL"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== retire_location task setup complete ==="
echo "Target Location: $LOCATION_NAME ($LOCATION_UUID)"
echo "Action required: Retire with reason 'End of season'"