#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up document_patient_phone_call task ==="

# 1. Wait for LibreHealth to be ready
wait_for_librehealth 120

# 2. Record Start Time for Anti-Gaming
# using date +%s is standard, but for SQL comparison we might want ISO format later
# sticking to timestamp for file checks
date +%s > /tmp/task_start_time.txt
# Also get DB time just in case of clock skew, though docker usually syncs
DB_START_TIME=$(librehealth_query "SELECT NOW()")

# 3. Select a Random Patient (Preferably one with meds)
echo "Selecting patient..."
# Try to find a patient who has medications in the 'lists' table
PATIENT_ID=$(librehealth_query "
    SELECT l.pid 
    FROM lists l 
    JOIN patient_data p ON l.pid = p.pid 
    WHERE l.type='medication' AND l.title != '' 
    ORDER BY RAND() LIMIT 1
")

# Fallback if no patients have meds (unlikely in NHANES but possible)
if [ -z "$PATIENT_ID" ]; then
    echo "No patients with meds found, selecting random patient..."
    PATIENT_ID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname!='' ORDER BY RAND() LIMIT 1")
    MED_NAME="Lisinopril"
else
    # Get the actual med name
    MED_NAME=$(librehealth_query "SELECT title FROM lists WHERE pid=$PATIENT_ID AND type='medication' LIMIT 1")
fi

# Get Patient Demographics
PATIENT_FNAME=$(librehealth_query "SELECT fname FROM patient_data WHERE pid=$PATIENT_ID")
PATIENT_LNAME=$(librehealth_query "SELECT lname FROM patient_data WHERE pid=$PATIENT_ID")
PATIENT_DOB=$(librehealth_query "SELECT DOB FROM patient_data WHERE pid=$PATIENT_ID")

echo "Selected Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_ID)"
echo "Medication: $MED_NAME"

# 4. Generate the Call Details File for the Agent
CALL_DETAILS_FILE="/home/ga/Desktop/call_details.txt"
cat > "$CALL_DETAILS_FILE" <<EOF
URGENT PHONE MESSAGE
-------------------
Time: $(date +"%H:%M")
Patient: $PATIENT_FNAME $PATIENT_LNAME
DOB: $PATIENT_DOB

Message:
Patient called the triage line. They reported losing their bottle of $MED_NAME 
on the bus this morning. They have 0 pills remaining and are requesting an 
emergency refill sent to their pharmacy.

Action Required:
Please document this in the patient's chart under "Notes" (Patient Notes).
Do not just send a message; this needs to be a permanent chart note.
EOF

chmod 644 "$CALL_DETAILS_FILE"
chown ga:ga "$CALL_DETAILS_FILE"

# 5. Record Initial State (Count of notes for this patient)
INITIAL_NOTE_COUNT=$(librehealth_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_ID")

# 6. Save Ground Truth for export_result.sh / verifier
# We use Python to write JSON to avoid bash escaping hell
python3 -c "
import json
data = {
    'target_pid': $PATIENT_ID,
    'target_fname': '$PATIENT_FNAME',
    'target_lname': '$PATIENT_LNAME',
    'medication': '$MED_NAME',
    'initial_note_count': $INITIAL_NOTE_COUNT,
    'db_start_time': '$DB_START_TIME',
    'task_start_ts': $(cat /tmp/task_start_time.txt)
}
with open('/tmp/task_ground_truth.json', 'w') as f:
    json.dump(data, f)
"

# 7. Set up UI
# Ensure Firefox is closed then open to login
pkill -f firefox 2>/dev/null || true
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 8. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="