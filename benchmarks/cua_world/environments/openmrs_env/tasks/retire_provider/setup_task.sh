#!/bin/bash
# Setup: retire_provider task
# Creates a new active provider "Dr. Eleanor Arroway" via REST API so the agent has a target to retire.

echo "=== Setting up retire_provider task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_timestamp

# 1. Check if Provider already exists to avoid duplicates or dirty state
echo "Checking for existing provider 'Eleanor Arroway'..."
EXISTING_PROV_UUID=$(omrs_get "/provider?q=Eleanor+Arroway&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)

if [ -n "$EXISTING_PROV_UUID" ]; then
    echo "Found existing provider ($EXISTING_PROV_UUID). Un-retiring if needed..."
    # Ensure it is NOT retired
    omrs_post "/provider/$EXISTING_PROV_UUID" '{"retired": false, "retireReason": null}' > /dev/null || true
    PROVIDER_UUID="$EXISTING_PROV_UUID"
else
    # 2. Create Person
    echo "Creating Person: Eleanor Arroway..."
    PERSON_PAYLOAD='{
        "names": [{"givenName": "Eleanor", "familyName": "Arroway", "preferred": true}],
        "gender": "F",
        "birthdate": "1980-01-01"
    }'
    PERSON_RESP=$(omrs_post "/person" "$PERSON_PAYLOAD")
    PERSON_UUID=$(echo "$PERSON_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))" 2>/dev/null)

    if [ -z "$PERSON_UUID" ]; then
        echo "ERROR: Failed to create person."
        echo "Response: $PERSON_RESP"
        exit 1
    fi

    # 3. Create Provider
    echo "Creating Provider: PROV-ARROWAY..."
    PROVIDER_PAYLOAD="{\"person\": \"$PERSON_UUID\", \"identifier\": \"PROV-ARROWAY\"}"
    PROVIDER_RESP=$(omrs_post "/provider" "$PROVIDER_PAYLOAD")
    PROVIDER_UUID=$(echo "$PROVIDER_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))" 2>/dev/null)

    if [ -z "$PROVIDER_UUID" ]; then
        echo "ERROR: Failed to create provider."
        echo "Response: $PROVIDER_RESP"
        exit 1
    fi
fi

echo "Target Provider UUID: $PROVIDER_UUID"
echo "$PROVIDER_UUID" > /tmp/task_provider_uuid

# 4. Open Firefox to Home Page (Agent must navigate from here)
echo "Launching Firefox..."
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== retire_provider task setup complete ==="
echo ""
echo "TASK: Retire Provider 'Dr. Eleanor Arroway'"
echo "Reason: 'Sabbatical'"
echo "Target UUID: $PROVIDER_UUID"