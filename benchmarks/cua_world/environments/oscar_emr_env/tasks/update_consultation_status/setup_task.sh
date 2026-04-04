#!/bin/bash
# Setup script for Update Consultation Status task
# Creates a patient, a specialist, and a pending consultation request

echo "=== Setting up Update Consultation Status Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Patient Exists (Robert Crawley)
echo "Checking for patient Robert Crawley..."
PATIENT_ID=$(get_patient_id "Robert" "Crawley")

if [ -z "$PATIENT_ID" ]; then
    echo "Creating patient Robert Crawley..."
    oscar_query "INSERT INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, date_joined, lastUpdateDate) VALUES ('Crawley', 'Robert', 'M', '1960', '01', '01', 'Toronto', 'ON', 'M5V 1A1', '416-555-0199', '999998', '1234567890', 'ON', 'AC', CURDATE(), NOW());" 2>/dev/null
    PATIENT_ID=$(get_patient_id "Robert" "Crawley")
fi
echo "Patient ID: $PATIENT_ID"

# 2. Ensure Specialist Exists (Dr. Alice Wong - Cardiology)
echo "Checking for specialist Dr. Alice Wong..."
# Check professional_specialists table
SPEC_ID=$(oscar_query "SELECT spec_id FROM professional_specialists WHERE last_name='Wong' AND first_name='Alice' LIMIT 1")

if [ -z "$SPEC_ID" ]; then
    echo "Creating specialist Dr. Alice Wong..."
    oscar_query "INSERT INTO professional_specialists (last_name, first_name, type, street_address, city, province, postal_code, phone_number, fax_number) VALUES ('Wong', 'Alice', 'Cardiology', '123 Heart Blvd', 'Toronto', 'ON', 'M5G 2C4', '416-555-9999', '416-555-8888');" 2>/dev/null
    SPEC_ID=$(oscar_query "SELECT spec_id FROM professional_specialists WHERE last_name='Wong' AND first_name='Alice' LIMIT 1")
fi
echo "Specialist ID: $SPEC_ID"

# 3. Create Pending Consultation Request
# We need to ensure there isn't already one to avoid confusion, or use the existing one
echo "Checking for existing consultation request..."
REQUEST_ID=$(oscar_query "SELECT requestId FROM consultationRequest WHERE demographic_no='$PATIENT_ID' AND consultant_id='$SPEC_ID' AND status!='Completed' LIMIT 1")

if [ -z "$REQUEST_ID" ]; then
    echo "Creating new pending consultation request..."
    # Insert a request dated 21 days ago
    # Note: status '1' usually maps to 'Pending Specialist Appt' or similar in default Oscar
    REQUEST_DATE=$(date -d "21 days ago" +%Y-%m-%d)
    
    oscar_query "INSERT INTO consultationRequest (demographic_no, providerNo, consultant_id, requestDate, status, serviceDesc, reason) VALUES ('$PATIENT_ID', '999998', '$SPEC_ID', '$REQUEST_DATE', 'Pending Specialist Appt', 'Cardiology', 'Atrial Fibrillation - please assess');" 2>/dev/null
    
    REQUEST_ID=$(oscar_query "SELECT requestId FROM consultationRequest WHERE demographic_no='$PATIENT_ID' AND consultant_id='$SPEC_ID' AND requestDate='$REQUEST_DATE' LIMIT 1")
else
    echo "Resetting existing request $REQUEST_ID to Pending..."
    oscar_query "UPDATE consultationRequest SET status='Pending Specialist Appt', reason='Atrial Fibrillation - please assess' WHERE requestId='$REQUEST_ID'" 2>/dev/null
fi
echo "Target Request ID: $REQUEST_ID"

# 4. Save State for Verification
echo "$REQUEST_ID" > /tmp/target_request_id.txt
echo "$PATIENT_ID" > /tmp/target_patient_id.txt

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch Browser
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="
echo "Target: Update Consultation #$REQUEST_ID for Patient #$PATIENT_ID"