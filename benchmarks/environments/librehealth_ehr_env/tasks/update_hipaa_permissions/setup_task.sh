#!/bin/bash
set -e
echo "=== Setting up Update HIPAA Permissions Task ==="

source /workspace/scripts/task_utils.sh

# Target PID to use for Maria Rodriguez (hijacking an existing slot to ensure consistency)
TARGET_PID=5

# Wait for LibreHealth to be ready
wait_for_librehealth 60

echo "Preparing patient data..."

# 1. Reset the patient to 'Maria Rodriguez' with INCORRECT settings (opposite of goal)
# Goal: Voice=No(0), Mail=No(0), SMS=Yes(1)
# Setup: Voice=Yes(1), Mail=Yes(1), SMS=No(0)
# We also update the date to a past timestamp to detect changes
librehealth_query "UPDATE patient_data SET 
    fname='Maria', 
    lname='Rodriguez', 
    hipaa_voice=1, 
    hipaa_mail=1, 
    hipaa_allowsms=0,
    date='2020-01-01 12:00:00'
    WHERE pid=${TARGET_PID}"

# 2. Verify setup
CHECK_SETUP=$(librehealth_query "SELECT count(*) FROM patient_data WHERE pid=${TARGET_PID} AND fname='Maria' AND hipaa_voice=1")
if [ "$CHECK_SETUP" -ne "1" ]; then
    echo "ERROR: Failed to setup patient data."
    exit 1
fi
echo "Patient Maria Rodriguez (PID ${TARGET_PID}) reset to initial state."

# 3. Record Task Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 4. Record Initial DB State for comparison (full row hash or specific fields)
librehealth_query "SELECT hipaa_voice, hipaa_mail, hipaa_allowsms FROM patient_data WHERE pid=${TARGET_PID}" > /tmp/initial_db_state.txt

# 5. Launch Firefox at Login Page
echo "Launching browser..."
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target: Maria Rodriguez (PID ${TARGET_PID})"
echo "Initial State: Voice=Yes, Mail=Yes, SMS=No"
echo "Goal State:    Voice=No,  Mail=No,  SMS=Yes"