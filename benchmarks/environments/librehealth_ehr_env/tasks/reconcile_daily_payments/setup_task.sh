#!/bin/bash
set -e
echo "=== Setting up Reconcile Daily Payments Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 60

# 1. Select a random patient from the database
echo "Selecting random patient..."
# Get random PID, fname, lname, DOB
PATIENT_DATA=$(librehealth_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE fname IS NOT NULL AND lname IS NOT NULL ORDER BY RAND() LIMIT 1")

if [ -z "$PATIENT_DATA" ]; then
    echo "ERROR: No patients found in database!"
    exit 1
fi

PID=$(echo "$PATIENT_DATA" | awk '{print $1}')
FNAME=$(echo "$PATIENT_DATA" | awk '{print $2}')
LNAME=$(echo "$PATIENT_DATA" | awk '{print $3}')
DOB=$(echo "$PATIENT_DATA" | awk '{print $4}')

echo "Selected Patient: $FNAME $LNAME (PID: $PID)"

# 2. Write patient info to Desktop file for the agent
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/payer_info.txt << EOF
Patient Payment Information
---------------------------
First Name: $FNAME
Last Name:  $LNAME
DOB:        $DOB
Patient ID: $PID

Task: Record a $40.00 Cash payment for this patient.
EOF
chmod 644 /home/ga/Desktop/payer_info.txt
chown ga:ga /home/ga/Desktop/payer_info.txt

# 3. Record baseline state (anti-gaming)
# Record start timestamp
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time
echo "$PID" > /tmp/target_pid
echo "$FNAME" > /tmp/target_fname
echo "$LNAME" > /tmp/target_lname

# Record initial number of payments in ar_activity
INITIAL_PAYMENT_COUNT=$(librehealth_query "SELECT COUNT(*) FROM ar_activity" 2>/dev/null || echo "0")
echo "$INITIAL_PAYMENT_COUNT" > /tmp/initial_payment_count

# Clear any previous output file
rm -f /home/ga/Desktop/day_sheet.pdf

# 4. Prepare UI
# Start Firefox at login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Patient: $FNAME $LNAME"