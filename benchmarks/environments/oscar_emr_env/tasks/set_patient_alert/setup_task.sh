#!/bin/bash
# Setup script for Set Patient Alert task
# Ensures patient Robert Williams exists and has an EMPTY alert field

echo "=== Setting up Set Patient Alert Task ==="

source /workspace/scripts/task_utils.sh

# 1. Define Patient Details
FNAME="Robert"
LNAME="Williams"
DOB="1942-07-18"
YOB="1942"
MOB="07"
DAY="18"

# 2. Check if patient exists, create if not
echo "Checking for patient $FNAME $LNAME ($DOB)..."
PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$FNAME' AND last_name='$LNAME' AND year_of_birth='$YOB' AND month_of_birth='$MOB' AND date_of_birth='$DAY' LIMIT 1")

if [ -z "$PATIENT_ID" ]; then
    echo "Patient not found. Creating Robert Williams..."
    # Insert realistic patient record
    oscar_query "INSERT INTO demographic (
        last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
        hin, ver, address, city, province, postal, phone, patient_status,
        provider_no, roster_status, date_joined, chart_no, alert
    ) VALUES (
        '$LNAME', '$FNAME', 'M', '$YOB', '$MOB', '$DAY',
        '6821445073', 'ON', '45 Elm Street', 'Hamilton', 'ON', 'L8P1A1',
        '905-555-0142', 'AC', '999998', 'RO',
        CURDATE(), 'RW001942', ''
    );" 
    
    # Retrieve ID of newly created patient
    PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$FNAME' AND last_name='$LNAME' AND year_of_birth='$YOB' LIMIT 1")
    echo "Created patient with ID: $PATIENT_ID"
else
    echo "Patient found with ID: $PATIENT_ID"
fi

# 3. CRITICAL: Clear the Alert field to ensure a clean start
echo "Clearing alert field for patient $PATIENT_ID..."
oscar_query "UPDATE demographic SET alert='' WHERE demographic_no='$PATIENT_ID'"

# 4. Verify the field is empty
CURRENT_ALERT=$(oscar_query "SELECT alert FROM demographic WHERE demographic_no='$PATIENT_ID'")
if [ -n "$CURRENT_ALERT" ]; then
    echo "WARNING: Alert field not empty! Content: '$CURRENT_ALERT'"
    # Force empty again just in case
    oscar_query "UPDATE demographic SET alert=NULL WHERE demographic_no='$PATIENT_ID'"
else
    echo "Verified alert field is empty."
fi

# 5. Record task state
date +%s > /tmp/task_start_time.txt
echo "$PATIENT_ID" > /tmp/target_patient_id.txt

# 6. Prepare Environment (Browser)
ensure_firefox_on_oscar

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="