#!/bin/bash
# Setup script for Reassign Task in OSCAR EMR

echo "=== Setting up Reassign Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Patient "Alice Tasker" exists
echo "Checking patient Alice Tasker..."
PATIENT_ID=$(get_patient_id "Alice" "Tasker")

if [ -z "$PATIENT_ID" ]; then
    echo "Creating patient Alice Tasker..."
    oscar_query "INSERT INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, phone, provider_no, patient_status, date_joined) VALUES ('Tasker', 'Alice', 'F', '1980', '01', '1980-01-01', '416-555-9999', '999998', 'AC', CURDATE());"
    PATIENT_ID=$(get_patient_id "Alice" "Tasker")
fi
echo "Patient ID: $PATIENT_ID"

# 2. Ensure "Locum Doctor" exists (Provider 999997)
echo "Checking Locum Doctor provider..."
LOCUM_EXISTS=$(oscar_query "SELECT count(*) FROM provider WHERE provider_no='999997'")
if [ "$LOCUM_EXISTS" -eq 0 ]; then
    echo "Creating Locum Doctor (999997)..."
    oscar_query "INSERT INTO provider (provider_no, last_name, first_name, provider_type, status, ohip_no) VALUES ('999997', 'Doctor', 'Locum', 'doctor', '1', '111111');"
fi

# 3. Ensure "Dr. Sarah Chen" exists (Provider 999998)
# Usually created by default setup, but verifying
CHEN_EXISTS=$(oscar_query "SELECT count(*) FROM provider WHERE provider_no='999998'")
if [ "$CHEN_EXISTS" -eq 0 ]; then
    echo "Creating Dr. Sarah Chen (999998)..."
    oscar_query "INSERT INTO provider (provider_no, last_name, first_name, provider_type, status, ohip_no) VALUES ('999998', 'Chen', 'Sarah', 'doctor', '1', '222222');"
fi

# 4. Create the Tickler Task
# Clean up any previous attempts to avoid confusion
oscar_query "DELETE FROM tickler WHERE demographic_no='$PATIENT_ID' AND message LIKE '%MRI Brain Results%'"

echo "Creating Tickler task..."
# Insert new tickler
oscar_query "INSERT INTO tickler (demographic_no, message, assigned_to, priority, status, task_date, create_date) VALUES ('$PATIENT_ID', 'MRI Brain Results - Abnormal', '999997', 'Normal', 'A', CURDATE(), NOW());"

# Retrieve the ID of the created tickler for verification
TICKLER_ID=$(oscar_query "SELECT tickler_no FROM tickler WHERE demographic_no='$PATIENT_ID' AND message LIKE '%MRI Brain Results%' ORDER BY tickler_no DESC LIMIT 1")
echo "$TICKLER_ID" > /tmp/target_tickler_id.txt
echo "Created Tickler ID: $TICKLER_ID"

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch Application
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="