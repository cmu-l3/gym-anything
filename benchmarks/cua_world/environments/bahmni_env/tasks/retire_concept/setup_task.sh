#!/bin/bash
set -u

echo "=== Setting up retire_concept task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenMRS to be ready
if ! wait_for_bahmni 600; then
    echo "ERROR: OpenMRS not reachable"
    exit 1
fi

echo "OpenMRS is ready. Preparing target concept..."

# Defined UUIDs for standard metadata (CIEL/Standard OpenMRS)
# Datatype: N/A
DATATYPE_UUID="8d4a4c94-c2cc-11de-8d13-0010c6dffd0f"
# Class: Misc
CLASS_UUID="8d492774-c2cc-11de-8d13-0010c6dffd0f"
TARGET_NAME="Duplicate Diagnosis Code"

# Check if concept exists
EXISTING_CONCEPT=$(openmrs_api_get "/concept?q=${TARGET_NAME// /%20}&v=full")
CONCEPT_UUID=$(echo "$EXISTING_CONCEPT" | python3 -c "import sys, json; res=json.load(sys.stdin).get('results', []); print(res[0]['uuid']) if res else print('')")

if [ -n "$CONCEPT_UUID" ]; then
    echo "Concept exists ($CONCEPT_UUID). Ensuring it is NOT retired..."
    # Un-retire it to ensure clean state
    openmrs_api_post "/concept/$CONCEPT_UUID" '{"retired": false, "retireReason": ""}' > /dev/null
    echo "Concept un-retired."
else
    echo "Concept does not exist. Creating it..."
    # Create new concept
    PAYLOAD=$(cat <<EOF
{
  "names": [
    {
      "name": "$TARGET_NAME",
      "locale": "en",
      "conceptNameType": "FULLY_SPECIFIED"
    }
  ],
  "datatype": "$DATATYPE_UUID",
  "conceptClass": "$CLASS_UUID"
}
EOF
)
    CREATE_RESP=$(openmrs_api_post "/concept" "$PAYLOAD")
    CONCEPT_UUID=$(echo "$CREATE_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uuid', ''))")
    
    if [ -z "$CONCEPT_UUID" ]; then
        echo "ERROR: Failed to create concept. Response:"
        echo "$CREATE_RESP"
        exit 1
    fi
    echo "Created concept: $CONCEPT_UUID"
fi

# Save UUID for verification reference (though verifier will look up by name)
echo "$CONCEPT_UUID" > /tmp/target_concept_uuid.txt

# Start Browser
echo "Starting browser..."
start_browser "https://localhost/bahmni/home"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="