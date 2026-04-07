#!/bin/bash
set -e
echo "=== Setting up add_problem_list_entry task ==="

# 1. Record task start time for anti-gaming (file modification/creation checks)
date +%s > /tmp/task_start_time.txt

# 2. Select a target patient from the database
# We look for a patient in the demographics table. Synthea data should be loaded.
echo "Selecting target patient..."
TARGET_DATA=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT pid, firstname, lastname FROM demographics WHERE active=1 ORDER BY RAND() LIMIT 1" 2>/dev/null)

if [ -z "$TARGET_DATA" ]; then
    echo "ERROR: No patients found in database. Using fallback."
    # Fallback to creating a dummy patient or failing if strict
    exit 1
fi

TARGET_PID=$(echo "$TARGET_DATA" | awk '{print $1}')
TARGET_FNAME=$(echo "$TARGET_DATA" | awk '{print $2}')
TARGET_LNAME=$(echo "$TARGET_DATA" | awk '{print $3}')

# 3. Save target info for the agent to read
echo "${TARGET_FNAME} ${TARGET_LNAME}" > /tmp/target_patient.txt
echo "${TARGET_PID}" > /tmp/target_patient_pid.txt

echo "Target Patient: ${TARGET_FNAME} ${TARGET_LNAME} (PID: ${TARGET_PID})"

# 4. Clean State: Remove any existing 'Hypertension' issues for this patient
# This ensures we are testing the agent's ability to add it, not finding an existing one.
echo "Cleaning existing hypertension issues for patient..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM issues WHERE pid=${TARGET_PID} AND (issue LIKE '%Hypertension%' OR icd LIKE '%I10%');" 2>/dev/null || true

# 5. Record Initial State (count of issues for this patient)
INITIAL_ISSUE_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT COUNT(*) FROM issues WHERE pid=${TARGET_PID}" 2>/dev/null || echo "0")
echo "$INITIAL_ISSUE_COUNT" > /tmp/initial_issue_count.txt

# 6. Prepare Browser Environment
# Kill existing instances
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean profile locks
rm -f /home/ga/.mozilla/firefox/*.default-release/lock
rm -f /home/ga/.mozilla/firefox/*.default-release/.parentlock

# Start Firefox pointing to NOSH login
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' > /tmp/firefox.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take Initial Screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="