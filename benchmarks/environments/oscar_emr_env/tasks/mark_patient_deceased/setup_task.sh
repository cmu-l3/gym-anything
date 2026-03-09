#!/bin/bash
# Setup script for Mark Patient Deceased task in OSCAR EMR

echo "=== Setting up Mark Patient Deceased Task ==="

source /workspace/scripts/task_utils.sh

# 1. Define Patient Details
PATIENT_FNAME="Arthur"
PATIENT_LNAME="Morgan"
# Calculate yesterday's date
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
# Save target date for export script to use later
echo "$YESTERDAY" > /tmp/target_death_date.txt
echo "Target Date of Death: $YESTERDAY"

# 2. Check/Create Patient
# We remove him first to ensure a clean state (active, no death date)
echo "Resetting patient record..."
EXISTING_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$PATIENT_FNAME' AND last_name='$PATIENT_LNAME' LIMIT 1")

if [ -n "$EXISTING_ID" ]; then
    # Reset existing patient to Active and clear death date
    oscar_query "UPDATE demographic SET patient_status='AC', date_of_death=NULL, reason_for_status_change='' WHERE demographic_no='$EXISTING_ID'"
    PATIENT_ID="$EXISTING_ID"
    echo "Reset existing patient (ID: $PATIENT_ID) to Active."
else
    # Create new patient
    # Using a high ID range or auto-increment
    oscar_query "INSERT INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, address, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('$PATIENT_LNAME', '$PATIENT_FNAME', 'M', '1963', '08', '15', '123 Horseshoe Overlook', 'Valentine', 'NE', '69201', '555-0199', '999998', '9991112223', 'ON', 'AC', NOW());"
    PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$PATIENT_FNAME' AND last_name='$PATIENT_LNAME' LIMIT 1")
    echo "Created new patient (ID: $PATIENT_ID)."
fi

# 3. Record Task Start State
# Save ID for export script
echo "$PATIENT_ID" > /tmp/task_patient_id.txt
date +%s > /tmp/task_start_time.txt

# 4. Launch Application
ensure_firefox_on_oscar

# 5. Capture Initial Evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Patient: Arthur Morgan (ID: $PATIENT_ID)"
echo "Current Status: Active"
echo "Target: Change to Deceased (DE) with date $YESTERDAY"