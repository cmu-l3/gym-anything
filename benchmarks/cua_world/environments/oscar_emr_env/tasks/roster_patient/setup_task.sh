#!/bin/bash
# Setup script for Roster Patient task in OSCAR EMR

echo "=== Setting up Roster Patient Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Michael Chang exists and is NOT rostered
echo "Preparing patient record for Michael Chang..."

# Check if patient exists
PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Michael' AND last_name='Chang' LIMIT 1")

if [ -n "$PATIENT_ID" ]; then
    echo "Patient found (ID: $PATIENT_ID). Resetting roster status..."
    # Reset to Not Rostered
    oscar_query "UPDATE demographic SET roster_status='NR', roster_date=NULL, provider_no='999998' WHERE demographic_no='$PATIENT_ID'"
else
    echo "Patient not found. Creating Michael Chang..."
    # Insert new patient
    oscar_query "INSERT INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, roster_status, lastUpdateDate) VALUES ('Chang', 'Michael', 'M', '1982', '03', '15', 'Toronto', 'ON', 'M5V 2B7', '416-555-8812', '999998', '5558829912', 'ON', 'AC', 'NR', NOW());"
    PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Michael' AND last_name='Chang' LIMIT 1")
fi

echo "Patient prepared: Michael Chang (ID: $PATIENT_ID, Status: NR)"

# 2. Record task start time for verification
date +%s > /tmp/task_start_time.txt
date +%Y-%m-%d > /tmp/task_start_date.txt

# 3. Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="