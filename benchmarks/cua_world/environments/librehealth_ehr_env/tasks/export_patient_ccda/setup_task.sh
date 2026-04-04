#!/bin/bash
echo "=== Setting up Export Patient C-CDA Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth EHR is ready
wait_for_librehealth 120

# Create output directory
mkdir -p /home/ga/Documents/Transfer
# Remove any existing export to prevent false positives
rm -f /home/ga/Documents/Transfer/export.xml

# Select a target patient from the database (using offset to vary from other tasks)
# We want a patient that likely has some data
echo "Selecting target patient..."
PATIENT_JSON=$(librehealth_query "SELECT CONCAT('{\"pid\":', pid, ',\"fname\":\"', fname, '\",\"lname\":\"', lname, '\",\"dob\":\"', DOBS, '\"}') FROM patient_data WHERE pid > 5 ORDER BY pid ASC LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_JSON" ]; then
    # Fallback if DB query fails or is empty
    PATIENT_JSON='{"pid":1,"fname":"Cora","lname":"Tester","dob":"1980-01-01"}'
fi

# Extract details (simple parsing since we control the query format)
PID=$(echo "$PATIENT_JSON" | grep -oP '"pid":\K\d+')
FNAME=$(echo "$PATIENT_JSON" | grep -oP '"fname":"\K[^"]+')
LNAME=$(echo "$PATIENT_JSON" | grep -oP '"lname":"\K[^"]+')
DOB=$(echo "$PATIENT_JSON" | grep -oP '"dob":"\K[^"]+')

echo "Target Patient: $FNAME $LNAME (PID: $PID)"

# Create the request file for the agent
cat > /home/ga/Desktop/transfer_request.txt << EOF
URGENT TRANSFER REQUEST

Patient Name: $FNAME $LNAME
Date of Birth: $DOB
MRN/PID: $PID

Request:
Please export the full Continuity of Care (C-CDA/CCR) record for this patient.
Save the XML file to: /home/ga/Documents/Transfer/export.xml
EOF

# Save target info for verification
echo "$PATIENT_JSON" > /tmp/target_patient_info.json

# Restart Firefox at login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="