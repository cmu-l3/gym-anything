#!/bin/bash
# Setup script for Inactivate Patient task
# Ensures patient 'Maria Santos' exists and has status 'AC' (Active)

echo "=== Setting up Inactivate Patient Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Oscar to be ready
wait_for_oscar_http 300

# 2. Prepare Patient Data (Maria Santos)
FNAME="Maria"
LNAME="Santos"
DOB="1978-06-22"
DEMO_NO="10050" # Fixed ID for reliability

echo "Ensuring patient $FNAME $LNAME exists with status AC..."

# Check if patient exists
COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE demographic_no='$DEMO_NO'" || echo "0")

if [ "$COUNT" -eq "0" ]; then
    # Insert new patient
    echo "Inserting patient record..."
    oscar_query "INSERT INTO demographic (
        demographic_no, last_name, first_name, sex, date_of_birth, 
        hin, ver, address, city, province, postal, phone, phone2, 
        email, patient_status, provider_no, roster_status, 
        date_joined, chart_no, family_doctor, lastUpdateDate
    ) VALUES (
        '$DEMO_NO', '$LNAME', '$FNAME', 'F', '$DOB', 
        '9876543217', 'AB', '445 Maple Drive', 'Toronto', 'ON', 'M5V2T6', 
        '416-555-0198', '416-555-0199', 'maria.santos@email.com', 
        'AC', '999998', 'RO', 
        '2019-03-15', '$DEMO_NO', 'Chen, Sarah', NOW()
    );"
else
    # Update existing patient to ensure Active status and correct details
    echo "Resetting existing patient status to AC..."
    oscar_query "UPDATE demographic SET 
        patient_status='AC', 
        first_name='$FNAME', 
        last_name='$LNAME', 
        date_of_birth='$DOB',
        lastUpdateDate=DATE_SUB(NOW(), INTERVAL 1 DAY) 
        WHERE demographic_no='$DEMO_NO';"
fi

# 3. Record Task Start Time (for anti-gaming verification)
# We use Python to get a precise timestamp compatible with SQL comparisons if needed
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 4. Record Initial State
INITIAL_STATUS=$(oscar_query "SELECT patient_status FROM demographic WHERE demographic_no='$DEMO_NO'")
echo "Initial Status: $INITIAL_STATUS"
if [ "$INITIAL_STATUS" != "AC" ]; then
    echo "ERROR: Failed to set initial status to AC"
    exit 1
fi

# 5. Launch Firefox
ensure_firefox_on_oscar

# 6. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="