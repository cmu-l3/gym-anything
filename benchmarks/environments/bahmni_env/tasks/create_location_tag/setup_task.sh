#!/bin/bash
set -u

echo "=== Setting up create_location_tag task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is reachable
echo "Waiting for OpenMRS to be ready..."
if ! wait_for_bahmni 300; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Clean state: Ensure the tag "Telehealth Endpoint" does NOT exist
echo "Ensuring clean state (removing existing tag if present)..."
TAG_QUERY=$(openmrs_api_get "/locationtag?q=Telehealth+Endpoint&v=default")
EXISTING_TAG_UUID=$(echo "$TAG_QUERY" | python3 -c "import sys, json; data=json.load(sys.stdin); results=data.get('results', []); print(results[0]['uuid']) if results else print('')")

if [ -n "$EXISTING_TAG_UUID" ]; then
    echo "Found existing tag ($EXISTING_TAG_UUID), removing it..."
    curl -sk -X DELETE \
        -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/locationtag/${EXISTING_TAG_UUID}?purge=true" 2>/dev/null || true
fi

# Ensure "Registration Desk" location exists (it should be in standard seed data)
LOC_QUERY=$(openmrs_api_get "/location?q=Registration+Desk&v=default")
LOC_UUID=$(echo "$LOC_QUERY" | python3 -c "import sys, json; data=json.load(sys.stdin); results=data.get('results', []); print(results[0]['uuid']) if results else print('')")

if [ -z "$LOC_UUID" ]; then
    echo "ERROR: Target location 'Registration Desk' not found. Seed data may be missing."
    exit 1
fi
echo "Target location verified: $LOC_UUID"

# Record initial tag count
INITIAL_TAGS=$(openmrs_api_get "/locationtag" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_TAGS" > /tmp/initial_tag_count.txt

# Start browser at OpenMRS Admin Login
# We point directly to /openmrs/admin/index.htm to save the agent navigation steps from the home page
START_URL="${OPENMRS_BASE_URL}/admin/index.htm"

echo "Starting browser at $START_URL..."
start_browser "$START_URL" 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="