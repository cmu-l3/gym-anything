#!/bin/bash
# Setup script for Complete Lab Requisition task

echo "=== Setting up Lab Requisition Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure patient Maria Santos exists
# Check if she exists
PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1")

if [ -z "$PATIENT_ID" ]; then
    echo "Creating patient Maria Santos..."
    oscar_query "INSERT INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) 
    VALUES ('Santos', 'Maria', 'F', '1975', '08', '22', 'Toronto', 'ON', 'M5T 1R3', '416-555-0198', '999998', '7642891035', 'ON', 'AC', NOW());"
    
    PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1")
fi

echo "Patient Maria Santos ID: $PATIENT_ID"

# 2. Add clinical context (Diabetes diagnosis)
# Check if diagnosis exists
DX_COUNT=$(oscar_query "SELECT COUNT(*) FROM dxresearch WHERE demographic_no='$PATIENT_ID' AND dx_code='250'" || echo "0")
if [ "$DX_COUNT" -eq "0" ]; then
    echo "Adding diabetes diagnosis..."
    oscar_query "INSERT INTO dxresearch (demographic_no, dx_code, diagnosis_desc, status, date_diagnosis) VALUES ('$PATIENT_ID', '250', 'Diabetes Mellitus', 'A', '2020-01-15');"
fi

# 3. Add a past HbA1c result for context (simulating need for follow-up)
# This goes into measurements table (simplified)
oscar_query "INSERT INTO measurements (demographic_no, dataField, dataValue, dateObserved) VALUES ('$PATIENT_ID', 'HbA1c', '7.2', DATE_SUB(NOW(), INTERVAL 4 MONTH));" 2>/dev/null || true

# 4. Record baseline state
# Count existing lab requisitions for this patient to detect new ones later
INITIAL_FORM_COUNT=$(oscar_query "SELECT COUNT(*) FROM formLabReq WHERE demographic_no='$PATIENT_ID'" 2>/dev/null || echo "0")
# Fallback to generic form table if specific table differs in this version
if [ -z "$INITIAL_FORM_COUNT" ] || [ "$INITIAL_FORM_COUNT" = "0" ]; then
    INITIAL_FORM_COUNT=$(oscar_query "SELECT COUNT(*) FROM form WHERE demographic_no='$PATIENT_ID' AND formName LIKE '%Lab%'" 2>/dev/null || echo "0")
fi

echo "$INITIAL_FORM_COUNT" > /tmp/initial_form_count
echo "$PATIENT_ID" > /tmp/task_patient_id
date +%s > /tmp/task_start_time

echo "Initial form count: $INITIAL_FORM_COUNT"

# 5. Launch Firefox
ensure_firefox_on_oscar

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="