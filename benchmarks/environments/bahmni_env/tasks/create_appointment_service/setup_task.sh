#!/bin/bash
set -e
echo "=== Setting up Create Appointment Service Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Wait for OpenMRS/Bahmni to be ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni API is not reachable"
    exit 1
fi

# 3. Clean up: Delete the service if it already exists (Idempotency)
# We query by name to find if it exists
echo "Checking for existing 'Nutrition Counseling' service..."
# Note: The Appointments module API might differ slightly depending on version, 
# but usually follows standard REST patterns.
SERVICE_SEARCH=$(openmrs_api_get "/appointmentscheduling/service?q=Nutrition&v=default")
EXISTING_UUID=$(echo "$SERVICE_SEARCH" | python3 -c "import sys, json; res=json.load(sys.stdin); results=res.get('results', []); print(results[0]['uuid'] if results else '')")

if [ -n "$EXISTING_UUID" ]; then
    echo "Removing pre-existing service (UUID: $EXISTING_UUID)..."
    # Purge the service to completely remove it
    curl -sk -X DELETE -u "$BAHMNI_ADMIN_USERNAME:$BAHMNI_ADMIN_PASSWORD" \
      "${OPENMRS_API_URL}/appointmentscheduling/service/$EXISTING_UUID?purge=true"
    echo "Pre-existing service removed."
fi

# 4. Launch Browser to Bahmni Home
echo "Launching browser..."
# Using start_browser from task_utils which handles SSL warnings
start_browser "$BAHMNI_LOGIN_URL" 4

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="