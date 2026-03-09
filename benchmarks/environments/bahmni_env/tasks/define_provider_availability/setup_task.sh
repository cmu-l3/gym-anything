#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: define_provider_availability@1 ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for API to be ready
wait_for_bahmni 300

# 2. Ensure 'Superman' is a provider
# We need the UUID of the Person 'Superman' to create a Provider if missing.
echo "Checking Provider status for 'Superman'..."
SUPERMAN_USER_JSON=$(openmrs_api_get "/user?q=superman&v=full")
SUPERMAN_PERSON_UUID=$(echo "$SUPERMAN_USER_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['results'][0]['person']['uuid'])
except:
    print('')
")

if [ -n "$SUPERMAN_PERSON_UUID" ]; then
    # Check if provider exists
    PROV_EXIST=$(openmrs_api_get "/provider?q=superman" | grep -c "\"uuid\"")
    if [ "$PROV_EXIST" -eq "0" ]; then
        echo "Creating Superman provider..."
        openmrs_api_post "/provider" "{\"person\": \"$SUPERMAN_PERSON_UUID\", \"identifier\": \"SUPERMAN\"}"
    else
        echo "Superman provider already exists."
    fi
else
    echo "WARNING: Superman user not found. Task may be difficult."
fi

# 3. Record initial state (count of blocks on target date)
# Target Date: 2026-03-12
TARGET_DATE="2026-03-12"
echo "Recording initial block count for $TARGET_DATE..."
INITIAL_BLOCKS_JSON=$(openmrs_api_get "/appointment/block?fromDate=${TARGET_DATE}T00:00:00.000&toDate=${TARGET_DATE}T23:59:59.999&v=default")
INITIAL_COUNT=$(echo "$INITIAL_BLOCKS_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_block_count.txt
echo "Initial blocks: $INITIAL_COUNT"

# 4. Start Browser
restart_browser "$BAHMNI_LOGIN_URL" 4

# Focus
focus_browser
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="