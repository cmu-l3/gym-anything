#!/bin/bash
set -e
echo "=== Setting up Record Retrospective Vitals Task ==="

# Source shared Bahmni task utilities
source /workspace/scripts/task_utils.sh

# 1. Record Task Start and Target Date
NOW_TS=$(date +%s)
echo "$NOW_TS" > /tmp/task_start_time.txt

# Calculate target date (10 days ago) for verification reference
# Format: YYYY-MM-DD
TARGET_DATE=$(date -d "10 days ago" '+%Y-%m-%d')
echo "$TARGET_DATE" > /tmp/target_date.txt
echo "Task Start: $(date)"
echo "Target Retrospective Date: $TARGET_DATE"

# 2. Wait for Bahmni/OpenMRS to be ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni API not reachable"
    exit 1
fi

# 3. Verify Patient Exists
# Robert Anderson is seeded as BAH000015
PATIENT_ID="BAH000015"
PATIENT_UUID=$(get_patient_uuid_by_identifier "$PATIENT_ID")

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Target patient $PATIENT_ID not found. Seeding may have failed."
    # Fallback: Try to find by name
    SEARCH_RESP=$(openmrs_api_get "/patient?q=Robert+Anderson&v=default")
    PATIENT_UUID=$(echo "$SEARCH_RESP" | python3 -c "import sys, json; res=json.load(sys.stdin).get('results',[]); print(res[0]['uuid'] if res else '')")
    
    if [ -z "$PATIENT_UUID" ]; then
        echo "CRITICAL: Robert Anderson not found by ID or Name."
        exit 1
    fi
fi

echo "Target Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/patient_uuid.txt

# 4. Cleanup Pre-existing specific data (if any) to ensure clean state
# We check if there's already an 82kg weight for this patient and void it if so
# Concept UUID for Weight: 5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
WEIGHT_CONCEPT="5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
EXISTING_OBS=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&concept=${WEIGHT_CONCEPT}&v=custom:(uuid,value,obsDatetime)")

# Python script to check for conflicting data
python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    for obs in results:
        if obs.get('value') == 82:
            print(f\"WARNING: Found existing 82kg observation {obs['uuid']}, should be cleaned up.\")
            # In a real scenario we might delete it, but for now we warn. 
            # The verifier checks for creation time > task start, so old data won't trigger false pass.
except:
    pass
" <<< "$EXISTING_OBS"

# 5. Launch Browser
# We launch Epiphany (standard for this env) pointed at the login page
if ! restart_browser "$BAHMNI_LOGIN_URL" 4; then
    echo "ERROR: Failed to start browser"
    exit 1
fi

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="