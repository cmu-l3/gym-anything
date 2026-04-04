#!/bin/bash
echo "=== Setting up Update Patient Demographics Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 60

# Target patient: Erin Warren (pid=2)
TARGET_PID=2
TARGET_NAME="Erin Warren"

# Verify target patient exists
VERIFY=$(librehealth_query "SELECT CONCAT(fname,' ',lname) FROM patient_data WHERE pid='${TARGET_PID}'" 2>/dev/null)
if [ -z "$VERIFY" ]; then
    echo "ERROR: Target patient ${TARGET_NAME} (pid=${TARGET_PID}) not found in database!"
    exit 1
fi
echo "Target patient verified: ${VERIFY} (pid=${TARGET_PID})"

# Reset the target patient's contact info to a known baseline (so the update is clear)
librehealth_query "UPDATE patient_data SET phone_home='503-555-0000', email='original@nhanes.test', city='Springfield' WHERE pid='${TARGET_PID}'" 2>/dev/null || true
echo "Reset contact info to baseline for patient pid=${TARGET_PID}"

# Record baseline (anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/lh_task_start
echo "$TARGET_PID" > /tmp/lh_target_pid
echo "Task start timestamp: $TASK_START"

# Open Firefox at the patient search page
restart_firefox "http://localhost:8000/interface/patient_file/patient_select.php"

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Update Patient Demographics Task Ready ==="
echo ""
echo "TASK: Update contact info for patient '${TARGET_NAME}' (pid=${TARGET_PID}):"
echo "  - Search for last name 'Warren' in the patient search"
echo "  - Click on 'Erin Warren' to open their chart"
echo "  - Go to Edit Demographics"
echo "  - Update: Home Phone -> 617-555-0233"
echo "  - Update: Email -> updated.contact@healthmail.test"
echo "  - Update: City -> Boston"
echo "  - Save the changes"
echo ""
echo "Login: admin / password"
