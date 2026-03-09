#!/bin/bash
# Setup script for Resolve Tickler task
# Creates a patient and a high-priority tickler assigned to the provider

set -e
echo "=== Setting up Resolve Tickler Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Oscar to be ready
wait_for_oscar_http 180

# 3. Ensure patient "Marcus Aurelius" exists
echo "Ensuring patient Marcus Aurelius exists..."
PATIENT_ID=$(get_patient_id "Marcus" "Aurelius")

if [ -z "$PATIENT_ID" ]; then
    echo "Creating patient Marcus Aurelius..."
    oscar_query "INSERT INTO demographic (
        last_name, first_name, sex, date_of_birth, hin, ver,
        patient_status, date_joined, chart_no, province, provider_no,
        phone, year_of_birth, month_of_birth,
        address, city, postal
    ) VALUES (
        'Aurelius', 'Marcus', 'M', '1960-04-26', '8976543210', 'ZZ',
        'AC', CURDATE(), '90001', 'ON', '999998',
        '416-555-0101', '1960', '04',
        '123 Rome Blvd', 'Toronto', 'M5V 2T6'
    );"
    PATIENT_ID=$(get_patient_id "Marcus" "Aurelius")
fi
echo "Patient ID: $PATIENT_ID"

# 4. Create the high-priority tickler
echo "Setting up tickler..."

# Clean up any existing ticklers for this patient to ensure a clean state
oscar_query "DELETE FROM tickler WHERE demographic_no='$PATIENT_ID'"

# Insert new tickler
# status 'A' = Active
# priority 'High'
# task_assigned_to '999998' (oscardoc)
MESSAGE="Critical Lab Result: Potassium 6.2 - Call Immediately"

oscar_query "INSERT INTO tickler (
    demographic_no, provider_no, task_assigned_to, 
    status, priority, message, 
    created_date, service_date, update_date
) VALUES (
    '$PATIENT_ID', '999998', '999998',
    'A', 'High', '$MESSAGE',
    NOW(), CURDATE(), NOW()
);"

# Get and save the Tickler ID for verification later
TICKLER_ID=$(oscar_query "SELECT tickler_no FROM tickler WHERE demographic_no='$PATIENT_ID' AND message LIKE '%Potassium%' LIMIT 1")

if [ -z "$TICKLER_ID" ]; then
    echo "ERROR: Failed to create tickler."
    exit 1
fi

echo "Created Tickler ID: $TICKLER_ID"
echo "$TICKLER_ID" > /tmp/target_tickler_id.txt

# 5. Launch Firefox
ensure_firefox_on_oscar

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="