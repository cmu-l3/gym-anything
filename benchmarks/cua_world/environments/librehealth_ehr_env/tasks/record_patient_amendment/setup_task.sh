#!/bin/bash
echo "=== Setting up Record Patient Amendment Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 60

# 1. Identify Target Patient (Brandie Sammet)
PATIENT_FNAME="Brandie"
PATIENT_LNAME="Sammet"

echo "Locating patient: $PATIENT_FNAME $PATIENT_LNAME..."
PID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null)

if [ -z "$PID" ] || [ "$PID" == "0" ]; then
    echo "ERROR: Patient $PATIENT_FNAME $PATIENT_LNAME not found in database!"
    # Fallback to creating the patient if missing (unlikely with NHANES but safe)
    librehealth_query "INSERT INTO patient_data (fname, lname, sex, DOB) VALUES ('$PATIENT_FNAME', '$PATIENT_LNAME', 'Female', '1980-01-01')"
    PID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null)
    echo "Created fallback patient with PID: $PID"
else
    echo "Found patient PID: $PID"
fi

# Save PID for export script
echo "$PID" > /tmp/target_pid.txt

# 2. Record Initial State (Anti-Gaming)
# Count existing amendments for this patient
INITIAL_AMEND_COUNT=$(librehealth_query "SELECT COUNT(*) FROM amendments WHERE pid='$PID'" 2>/dev/null || echo "0")
echo "$INITIAL_AMEND_COUNT" > /tmp/initial_amendment_count
echo "Initial amendment count for PID $PID: $INITIAL_AMEND_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_time

# 3. Reset UI State
# Restart Firefox to login page to ensure clean start
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 4. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="