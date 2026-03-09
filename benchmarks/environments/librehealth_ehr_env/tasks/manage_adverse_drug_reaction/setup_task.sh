#!/bin/bash
set -e
echo "=== Setting up Manage Adverse Drug Reaction Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for LibreHealth
wait_for_librehealth 60

# 2. Select a target patient (First patient in DB usually ID 1 or similar)
# We pick a patient who doesn't already have this specific medication to avoid conflicts,
# or we clean it up first.
TARGET_PID=$(librehealth_query "SELECT pid FROM patient_data LIMIT 1" 2>/dev/null)
TARGET_FNAME=$(librehealth_query "SELECT fname FROM patient_data WHERE pid=${TARGET_PID}" 2>/dev/null)
TARGET_LNAME=$(librehealth_query "SELECT lname FROM patient_data WHERE pid=${TARGET_PID}" 2>/dev/null)
TARGET_NAME="${TARGET_FNAME} ${TARGET_LNAME}"

echo "Target Patient: ${TARGET_NAME} (PID: ${TARGET_PID})"

# 3. Clean slate: Remove any existing Lisinopril meds or allergies for this patient
librehealth_query "DELETE FROM lists WHERE pid=${TARGET_PID} AND (type='medication' OR type='allergy') AND (title LIKE '%Lisinopril%' OR title LIKE '%ACE Inhibitor%')" 2>/dev/null

# 4. Inject the ACTIVE medication (Start date 3 months ago, NO end date)
# 'activity'=1 means active.
START_DATE=$(date -d "3 months ago" +%Y-%m-%d)
librehealth_query "INSERT INTO lists (pid, type, date, title, begdate, activity, user) VALUES (${TARGET_PID}, 'medication', NOW(), 'Lisinopril 10mg', '${START_DATE}', 1, 'admin')" 2>/dev/null

echo "Injected active Lisinopril prescription for ${TARGET_NAME}"

# 5. Save patient info for the agent
echo "${TARGET_NAME}" > /tmp/task_patient_info.txt
# Also update the task description dynamically if possible, or just rely on the file.
# The task.json description has [PATIENT_NAME] placeholder, but since we can't edit task.json at runtime easily in this env,
# we rely on the agent reading the file or the generic instruction "Find the patient identified in /tmp/task_patient_info.txt".
# *However*, for better UX, we'll also write it to a sticky note on the desktop if we could, 
# but simply cat-ing it to a file the agent is told to read is standard.

# 6. Record Initial State (Anti-gaming)
INITIAL_MED_COUNT=$(librehealth_query "SELECT COUNT(*) FROM lists WHERE pid=${TARGET_PID} AND type='medication'" 2>/dev/null)
INITIAL_ALL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM lists WHERE pid=${TARGET_PID} AND type='allergy'" 2>/dev/null)
echo "${INITIAL_MED_COUNT}" > /tmp/initial_med_count
echo "${INITIAL_ALL_COUNT}" > /tmp/initial_all_count
date +%s > /tmp/task_start_time

# 7. Prepare Browser
# Kill any existing Firefox
pkill -f firefox || true
sleep 1
# Start Firefox at Login
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Patient: ${TARGET_NAME}"