#!/bin/bash
set -e
echo "=== Setting up Record Vital Signs Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Wait for LibreHealth EHR to be accessible
wait_for_librehealth 120

# Select a NHANES patient with a non-empty name
# Use OFFSET to pick a patient that's not the very first (more realistic)
echo "Selecting target patient from NHANES data..."
PATIENT_ROW=$(librehealth_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE fname != '' AND lname != '' AND LENGTH(fname) > 1 AND LENGTH(lname) > 1 ORDER BY pid LIMIT 1 OFFSET 15")

if [ -z "$PATIENT_ROW" ]; then
    echo "WARNING: No suitable patient found, trying without offset..."
    PATIENT_ROW=$(librehealth_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE fname != '' AND lname != '' ORDER BY pid LIMIT 1")
fi

PID=$(echo "$PATIENT_ROW" | awk '{print $1}')
FNAME=$(echo "$PATIENT_ROW" | awk '{print $2}')
LNAME=$(echo "$PATIENT_ROW" | awk '{print $3}')
DOB=$(echo "$PATIENT_ROW" | awk '{print $4}')

echo "Selected patient: $FNAME $LNAME (PID: $PID, DOB: $DOB)"

# Save patient info for the agent to read
cat > /tmp/target_patient.txt << EOF
Patient Name: $FNAME $LNAME
Date of Birth: $DOB
EOF

# Save PID for verification (hidden from task description but accessible to verifier)
echo "$PID" > /tmp/target_patient_pid.txt
chmod 644 /tmp/target_patient.txt
chmod 644 /tmp/target_patient_pid.txt

# Record initial vitals count for anti-gaming detection
INITIAL_VITALS_TOTAL=$(librehealth_query "SELECT COUNT(*) FROM form_vitals" 2>/dev/null || echo "0")
echo "$INITIAL_VITALS_TOTAL" > /tmp/initial_vitals_count.txt

# Restart Firefox at the login page (clean state)
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="