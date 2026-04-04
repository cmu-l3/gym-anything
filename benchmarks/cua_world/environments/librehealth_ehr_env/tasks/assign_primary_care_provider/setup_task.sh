#!/bin/bash
set -e
echo "=== Setting up Assign Primary Care Provider Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for LibreHealth EHR to be ready
wait_for_librehealth 120

# 2. Identify a target patient
# We prefer a patient who currently has NO provider assigned (providerID is NULL or 0)
# This ensures the task is a "new assignment" rather than a change.
echo "Selecting target patient..."

# Try to find a patient with no provider
TARGET_DATA=$(librehealth_query "SELECT pid, fname, lname FROM patient_data WHERE providerID IS NULL OR providerID = 0 OR providerID = '' LIMIT 1" 2>/dev/null)

# If no such patient exists (unlikely in large dataset, but possible), pick any patient and force provider to NULL
if [ -z "$TARGET_DATA" ]; then
    echo "No unassigned patient found. Forcing a patient to be unassigned..."
    # Pick the patient with PID 1 or the first available
    TARGET_DATA=$(librehealth_query "SELECT pid, fname, lname FROM patient_data LIMIT 1")
    PID=$(echo "$TARGET_DATA" | awk '{print $1}')
    if [ -n "$PID" ]; then
        librehealth_query "UPDATE patient_data SET providerID = NULL WHERE pid = ${PID}"
        echo "Reset provider for PID ${PID} to NULL"
    fi
fi

if [ -z "$TARGET_DATA" ]; then
    echo "ERROR: Could not find or prepare a target patient."
    exit 1
fi

# Parse the data
PID=$(echo "$TARGET_DATA" | awk '{print $1}')
FNAME=$(echo "$TARGET_DATA" | awk '{print $2}')
LNAME=$(echo "$TARGET_DATA" | awk '{print $3}')

echo "Target Patient: ${FNAME} ${LNAME} (PID: ${PID})"

# 3. Write patient details to Desktop for the agent
cat > /home/ga/Desktop/task_patient.txt << EOF
Patient Name: ${FNAME} ${LNAME}
Patient ID: ${PID}
Task: Assign Primary Care Provider to "Administrator"
EOF
chown ga:ga /home/ga/Desktop/task_patient.txt

# 4. Record initial state for verification
# We record the providerID (should be NULL/0) and the admin's user ID
ADMIN_ID=$(librehealth_query "SELECT id FROM users WHERE username='admin'")
INITIAL_PROVIDER_ID=$(librehealth_query "SELECT providerID FROM patient_data WHERE pid=${PID}")

# Handle empty/null result for provider ID
if [ -z "$INITIAL_PROVIDER_ID" ]; then INITIAL_PROVIDER_ID="0"; fi

echo "${PID}" > /tmp/task_pid.txt
echo "${ADMIN_ID}" > /tmp/task_admin_id.txt
echo "${INITIAL_PROVIDER_ID}" > /tmp/task_initial_provider_id.txt
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox at Login Page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 6. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target: ${FNAME} ${LNAME}"
echo "Admin ID: ${ADMIN_ID}"