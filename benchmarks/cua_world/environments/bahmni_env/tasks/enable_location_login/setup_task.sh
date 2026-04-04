#!/bin/bash
set -u

echo "=== Setting up Enable Location Login Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure Bahmni is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

TARGET_LOC="Telemedicine Wing"
echo "Configuring location: $TARGET_LOC"

# Check if the location already exists
# We use python to parse the JSON response cleanly
LOC_SEARCH=$(openmrs_api_get "/location?q=Telemedicine+Wing&v=default")
LOC_UUID=$(echo "$LOC_SEARCH" | python3 -c "import sys, json; \
data = json.load(sys.stdin); \
results = [r for r in data.get('results', []) if r.get('display', '').lower() == '$TARGET_LOC'.lower()]; \
print(results[0]['uuid']) if results else print('')")

if [ -n "$LOC_UUID" ]; then
  echo "Location exists (UUID: $LOC_UUID). Resetting configuration..."
  # Reset: Remove all tags to simulate the issue
  # We send an empty tags array. Note: OpenMRS API behavior varies, but sending empty list usually works
  # or we might need to send the object without tags.
  # Let's try sending empty tags list.
  PAYLOAD='{"tags": []}'
  openmrs_api_post "/location/$LOC_UUID" "$PAYLOAD" > /dev/null
  echo "Tags cleared for existing location."
else
  echo "Location does not exist. Creating it..."
  # Create new location with NO tags
  PAYLOAD='{
    "name": "'"$TARGET_LOC"'",
    "description": "New wing for remote consultations",
    "tags": []
  }'
  CREATE_RESP=$(openmrs_api_post "/location" "$PAYLOAD")
  LOC_UUID=$(echo "$CREATE_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uuid', ''))")
  
  if [ -z "$LOC_UUID" ]; then
    echo "ERROR: Failed to create location."
    echo "Response: $CREATE_RESP"
    exit 1
  fi
  echo "Created location with UUID: $LOC_UUID"
fi

# Double check the state to ensure it's "broken" (no tags)
VERIFY_STATE=$(openmrs_api_get "/location/$LOC_UUID?v=full")
TAG_COUNT=$(echo "$VERIFY_STATE" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('tags', [])))")

if [ "$TAG_COUNT" -ne 0 ]; then
  echo "WARNING: Failed to clear tags. Location still has $TAG_COUNT tags."
  # This might happen if 'Login Location' is default. We proceed but log it.
else
  echo "Verified: Location has 0 tags."
fi

# Launch Browser
echo "Launching browser..."
if ! restart_firefox "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

# Maximize and focus
focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="