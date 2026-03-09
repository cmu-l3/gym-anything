#!/bin/bash
echo "=== Setting up Record Patient Allergies Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running and accessible
wait_for_librehealth 60

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ------------------------------------------------------------------
# 1. Select a Target Patient
# ------------------------------------------------------------------
# We want a patient who doesn't already have these specific allergies to avoid confusion.
# We'll pick a random patient from the top 50 to ensure we get a valid one.

echo "Selecting target patient..."
# Get a list of PIDs and Names
PATIENT_LIST=$(librehealth_query "SELECT pid, fname, lname FROM patient_data LIMIT 50" 2>/dev/null)

if [ -z "$PATIENT_LIST" ]; then
    echo "ERROR: No patients found in database!"
    exit 1
fi

# Pick a random line (patient)
# Using shuf to pick one line
SELECTED_LINE=$(echo "$PATIENT_LIST" | shuf -n 1)
TARGET_PID=$(echo "$SELECTED_LINE" | awk '{print $1}')
TARGET_FNAME=$(echo "$SELECTED_LINE" | awk '{print $2}')
TARGET_LNAME=$(echo "$SELECTED_LINE" | awk '{print $3}')

echo "Selected Patient: $TARGET_FNAME $TARGET_LNAME (PID: $TARGET_PID)"

# ------------------------------------------------------------------
# 2. Clean State: Remove existing allergies for this patient
# ------------------------------------------------------------------
# To ensure the task is challenging and clean, we remove *any* existing allergies 
# for this specific patient so the agent starts with a blank slate (or at least 
# without the ones we are asking for).

librehealth_query "DELETE FROM lists WHERE pid='$TARGET_PID' AND type='allergy'" 2>/dev/null
echo "Cleared existing allergies for PID $TARGET_PID"

# ------------------------------------------------------------------
# 3. Write Patient Info to File for Agent
# ------------------------------------------------------------------
cat > /tmp/target_patient.txt << EOF
Target Patient Information
--------------------------
Patient ID: $TARGET_PID
Name: $TARGET_FNAME $TARGET_LNAME

Task: Record Penicillin and Sulfonamides allergies for this patient.
EOF

# Also save PID for the export script to use later
echo "$TARGET_PID" > /tmp/target_pid.txt

# ------------------------------------------------------------------
# 4. Record Initial State
# ------------------------------------------------------------------
# Should be 0 since we just deleted them
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM lists WHERE pid='$TARGET_PID' AND type='allergy'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_allergy_count.txt

# ------------------------------------------------------------------
# 5. UI Setup
# ------------------------------------------------------------------
# Start Firefox at the login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Target: $TARGET_FNAME $TARGET_LNAME (PID: $TARGET_PID)"