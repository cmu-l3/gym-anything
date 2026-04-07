#!/bin/bash
# Setup: create_provider_schedule
# Ensures the 'General Medicine' service exists and cleans up any existing blocks for tomorrow.

echo "=== Setting up create_provider_schedule task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Calculate "Tomorrow"
TOMORROW=$(date -d "+1 day" +%Y-%m-%d)
echo "Target Date: $TOMORROW"
echo "$TOMORROW" > /tmp/target_date.txt

# 1. Ensure 'General Medicine' Appointment Service exists
echo "Checking for 'General Medicine' service..."
SERVICE_CHECK=$(omrs_db_query "SELECT appointment_service_id FROM appointment_service WHERE name='General Medicine' AND voided=0;")

if [ -z "$SERVICE_CHECK" ]; then
    echo "Creating 'General Medicine' service..."
    # We insert directly into DB to ensure it's there, or via REST if preferred. 
    # Using SQL for speed/reliability in setup.
    omrs_db_query "INSERT INTO appointment_service (name, description, duration_mins, creator, date_created, voided, uuid) VALUES ('General Medicine', 'General checkups', 15, 1, NOW(), 0, UUID());"
fi

# 2. Get Provider ID for 'Super User'
PROVIDER_ID=$(omrs_db_query "SELECT provider_id FROM provider WHERE name='Super User' AND retired=0;" || echo "")
if [ -z "$PROVIDER_ID" ]; then
    # Fallback: look for provider associated with admin person (usually person_id 1)
    PROVIDER_ID=$(omrs_db_query "SELECT provider_id FROM provider WHERE person_id=1 AND retired=0;" || echo "")
fi
echo "Provider ID for Super User: $PROVIDER_ID"

# 3. Clean up existing blocks for this provider on the target date
if [ -n "$PROVIDER_ID" ]; then
    echo "Clearing existing blocks for provider $PROVIDER_ID on $TOMORROW..."
    omrs_db_query "UPDATE appointment_block SET voided=1, voided_by=1, date_voided=NOW(), void_reason='Task Setup Cleanup' WHERE provider_id=$PROVIDER_ID AND start_datetime BETWEEN '$TOMORROW 00:00:00' AND '$TOMORROW 23:59:59';"
fi

# 4. Record initial block count for verification
INITIAL_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM appointment_block WHERE voided=0;" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_block_count

# 5. Launch Firefox and login
APP_URL="http://localhost/openmrs/spa/appointments/calendar"
ensure_openmrs_logged_in "$APP_URL"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target Date: $TOMORROW"
echo "Provider: Super User"
echo "Service: General Medicine"
echo "Time: 09:00 - 17:00"