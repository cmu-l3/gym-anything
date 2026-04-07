#!/bin/bash
echo "=== Setting up Create Appointment Service Task ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (created_after check)
date +%s > /tmp/task_start_time.txt

# 1. Clean up: Remove the service if it already exists to ensure a fresh start
echo "Checking for existing 'Ergonomic Assessment' service..."

# We use the REST API to find and purge/retire existing types with this name
EXISTING_UUIDS=$(omrs_get "/appointmentscheduling/appointmenttype?q=Ergonomic+Assessment&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(i['uuid']) for i in r.get('results',[])]" 2>/dev/null || true)

if [ -n "$EXISTING_UUIDS" ]; then
    echo "Found existing service(s). Cleaning up..."
    while IFS= read -r uuid; do
        if [ -n "$uuid" ]; then
            # Try to purge (delete permanently) first
            omrs_delete "/appointmentscheduling/appointmenttype/$uuid?purge=true" 2>/dev/null || \
            # If purge fails (e.g. referenced data), just retire it
            omrs_delete "/appointmentscheduling/appointmenttype/$uuid" 2>/dev/null || true
            echo "  Removed/Retired: $uuid"
        fi
    done <<< "$EXISTING_UUIDS"
else
    echo "No existing service found. Clean state confirmed."
fi

# 2. Record initial count of appointment types
INITIAL_COUNT=$(omrs_get "/appointmentscheduling/appointmenttype?v=count" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('totalCount', 0))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_service_count

# 3. Open Firefox on the OpenMRS Home Page (Appointments app is accessible from here)
# We start at Home so the agent has to navigate to "Appointments" -> "Manage Services"
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Target: Create 'Ergonomic Assessment' (45 mins)"
echo "Start time: $(cat /tmp/task_start_time.txt)"