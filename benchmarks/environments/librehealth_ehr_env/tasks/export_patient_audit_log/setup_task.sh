#!/bin/bash
set -e
echo "=== Setting up Export Patient Audit Log Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure LibreHealth EHR is running
wait_for_librehealth 120

# 2. Verify Target Patient Exists (Brandie Sammet is in NHANES)
PATIENT_ID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname='Brandie' AND lname='Sammet' LIMIT 1")
if [ -z "$PATIENT_ID" ]; then
    echo "ERROR: Patient Brandie Sammet not found in database."
    exit 1
fi
echo "Target Patient: Brandie Sammet (PID: $PATIENT_ID)"

# 3. Generate a 'View' event to ensure there is something to report
# We simulate a chart view by hitting the patient file URL
echo "Generating audit log entry..."
curl -s -b /tmp/cookies.txt -c /tmp/cookies.txt \
    -d "new_login_session_management=1&authProvider=Default&authUser=admin&clearPass=password&languageChoice=1" \
    "http://localhost:8000/interface/login/login.php?site=default" > /dev/null

# Access the patient record to trigger a log entry
curl -s -b /tmp/cookies.txt "http://localhost:8000/interface/patient_file/summary/demographics.php?set_pid=$PATIENT_ID" > /dev/null
echo "Audit log entry seeded for PID $PATIENT_ID"

# 4. Clean up previous artifacts
rm -f /home/ga/Documents/brandie_sammet_audit.csv
mkdir -p /home/ga/Documents

# 5. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
date -I > /tmp/task_date_iso.txt

# 6. Start Firefox
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="