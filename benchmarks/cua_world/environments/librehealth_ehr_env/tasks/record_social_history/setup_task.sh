#!/bin/bash
set -e

echo "=== Setting up Record Social History Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for LibreHealth EHR to be accessible
wait_for_librehealth 120

# 1. Select a target patient (PID 1-200 to ensure data exists)
# We want a patient who has a name
echo "Selecting patient..."
PATIENT_JSON=$(docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e "
    SELECT JSON_OBJECT('pid', pid, 'fname', fname, 'lname', lname, 'dob', DOB)
    FROM patient_data
    WHERE fname IS NOT NULL AND fname != ''
      AND lname IS NOT NULL AND lname != ''
      AND pid BETWEEN 1 AND 200
    ORDER BY RAND()
    LIMIT 1;
" 2>/dev/null)

if [ -z "$PATIENT_JSON" ]; then
    echo "ERROR: Could not find suitable patient in database."
    exit 1
fi

# Extract details using python for reliability
PID=$(echo "$PATIENT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['pid'])")
FNAME=$(echo "$PATIENT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['fname'])")
LNAME=$(echo "$PATIENT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['lname'])")
DOB=$(echo "$PATIENT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['dob'])")

echo "Selected Patient: $FNAME $LNAME (PID: $PID)"
echo "$PID" > /tmp/task_target_pid.txt

# 2. Write patient info file for the agent
cat > /tmp/task_patient_info.txt << EOF
Patient for Social History Update:
  First Name: ${FNAME}
  Last Name: ${LNAME}
  PID: ${PID}
  Date of Birth: ${DOB}
EOF
chmod 644 /tmp/task_patient_info.txt

# 3. Record initial history state (to detect changes)
# We look at the 'history_data' table
INITIAL_HISTORY=$(docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e "
    SELECT JSON_OBJECT(
        'tobacco', tobacco,
        'alcohol', alcohol,
        'recreational_drugs', recreational_drugs,
        'exercise_patterns', exercise_patterns,
        'counseling', counseling
    )
    FROM history_data
    WHERE pid = ${PID}
    ORDER BY id DESC LIMIT 1;
" 2>/dev/null || echo "{}")

if [ -z "$INITIAL_HISTORY" ] || [ "$INITIAL_HISTORY" == "NULL" ]; then
    INITIAL_HISTORY="{}"
fi

echo "$INITIAL_HISTORY" > /tmp/task_initial_history.json
echo "Initial history state recorded."

# 4. Reset Firefox to login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="