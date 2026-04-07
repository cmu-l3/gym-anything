#!/bin/bash
set -e
echo "=== Setting up task: correct_patient_insurance ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth is accessible
wait_for_librehealth 60

# 1. Get PID for Brandie Sammet
PID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname='Brandie' AND lname='Sammet' LIMIT 1")

if [ -z "$PID" ]; then
    echo "Patient Brandie Sammet not found. Using first available patient."
    PID=$(librehealth_query "SELECT pid FROM patient_data LIMIT 1")
    # Update name metadata for verification if we switched patients (best effort)
    FNAME=$(librehealth_query "SELECT fname FROM patient_data WHERE pid='$PID'")
    LNAME=$(librehealth_query "SELECT lname FROM patient_data WHERE pid='$PID'")
    echo "Switched to patient: $FNAME $LNAME (PID: $PID)"
fi
echo "$PID" > /tmp/target_pid.txt

# 2. Ensure 'Blue Cross' Insurance Company exists
INS_CO_ID=$(librehealth_query "SELECT id FROM insurance_companies WHERE name='Blue Cross' LIMIT 1")
if [ -z "$INS_CO_ID" ]; then
    echo "Creating Blue Cross insurance company..."
    NEXT_IC_ID=$(librehealth_query "SELECT COALESCE(MAX(id),0)+1 FROM insurance_companies")
    librehealth_query "INSERT INTO insurance_companies (id, name, attn, cms_id) VALUES ($NEXT_IC_ID, 'Blue Cross', 'Claims Dept', 'BC001')"
    INS_CO_ID=$(librehealth_query "SELECT id FROM insurance_companies WHERE name='Blue Cross' LIMIT 1")
fi

# 3. Reset Insurance Data for Patient
# We want to force a specific initial state: Incorrect Policy Number, Zero Copay
echo "Resetting insurance data for PID $PID..."

# Remove existing primary insurance for this patient
librehealth_query "DELETE FROM insurance_data WHERE pid='$PID' AND type='primary'"

# Insert the 'Incorrect' record
# policy_number='Pending-Input', copay='0.00'
librehealth_query "INSERT INTO insurance_data (pid, type, provider, plan_name, policy_number, group_number, copay, date) VALUES ('$PID', 'primary', '$INS_CO_ID', 'HMO Basic', 'Pending-Input', 'GRP999', '0.00', NOW())"

# Get the ID of the record we just created (to verify it was updated, not replaced)
INITIAL_INS_ID=$(librehealth_query "SELECT id FROM insurance_data WHERE pid='$PID' AND type='primary' ORDER BY id DESC LIMIT 1")
echo "$INITIAL_INS_ID" > /tmp/initial_insurance_id.txt
echo "Created initial insurance record ID: $INITIAL_INS_ID"

# 4. Launch Firefox at Login
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="