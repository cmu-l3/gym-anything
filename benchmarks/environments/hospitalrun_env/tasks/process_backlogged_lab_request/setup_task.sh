#!/bin/bash
set -e
echo "=== Setting up process_backlogged_lab_request ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 2. Create Patient "Maria Santos" (P00055)
echo "Creating patient Maria Santos..."
PATIENT_ID="P00055"
# Note: HospitalRun expects data to be wrapped in a 'data' property for some versions,
# but the PouchDB/CouchDB sync logic often flattens it. We provide both for safety.
PATIENT_DOC=$(cat <<EOF
{
  "_id": "patient_p1_${PATIENT_ID}",
  "docType": "patient",
  "firstName": "Maria",
  "lastName": "Santos",
  "dateOfBirth": "1990-05-15",
  "sex": "Female",
  "patientId": "${PATIENT_ID}",
  "data": {
    "firstName": "Maria",
    "lastName": "Santos",
    "dateOfBirth": "1990-05-15",
    "sex": "Female",
    "patientId": "${PATIENT_ID}",
    "address": "123 Backlog Lane"
  }
}
EOF
)
hr_couch_put "patient_p1_${PATIENT_ID}" "$PATIENT_DOC"

# 3. Create OLD Request (The Target) - Date: 2025-01-10
# Timestamp: 1736467200000
TARGET_ID="lab_req_target_old"
TARGET_DOC=$(cat <<EOF
{
  "_id": "${TARGET_ID}",
  "docType": "pricing",
  "type": "lab",
  "name": "Malaria Smear",
  "patient": "Maria Santos",
  "patientId": "${PATIENT_ID}",
  "visitId": "visit_p1_v001",
  "status": "Requested",
  "requestDate": 1736467200000, 
  "date": "2025-01-10T09:00:00.000Z",
  "data": {
    "name": "Malaria Smear",
    "patient": "Maria Santos",
    "patientId": "${PATIENT_ID}",
    "status": "Requested",
    "requestDate": 1736467200000,
    "date": "2025-01-10T09:00:00.000Z",
    "notes": "Backlogged request from power outage week"
  }
}
EOF
)
hr_couch_put "${TARGET_ID}" "$TARGET_DOC"

# 4. Create NEW Request (The Distractor) - Date: 2025-01-17
# Timestamp: 1737072000000
DISTRACTOR_ID="lab_req_distractor_new"
DISTRACTOR_DOC=$(cat <<EOF
{
  "_id": "${DISTRACTOR_ID}",
  "docType": "pricing",
  "type": "lab",
  "name": "Malaria Smear",
  "patient": "Maria Santos",
  "patientId": "${PATIENT_ID}",
  "visitId": "visit_p1_v001",
  "status": "Requested",
  "requestDate": 1737072000000,
  "date": "2025-01-17T09:00:00.000Z",
  "data": {
    "name": "Malaria Smear",
    "patient": "Maria Santos",
    "patientId": "${PATIENT_ID}",
    "status": "Requested",
    "requestDate": 1737072000000,
    "date": "2025-01-17T09:00:00.000Z",
    "notes": "Routine follow-up"
  }
}
EOF
)
hr_couch_put "${DISTRACTOR_ID}" "$DISTRACTOR_DOC"

# Save IDs for export script to use
echo "${TARGET_ID}" > /tmp/target_doc_id.txt
echo "${DISTRACTOR_ID}" > /tmp/distractor_doc_id.txt

# 5. Fix PouchDB Sync (Crucial for HospitalRun to see new CouchDB docs)
fix_offline_sync

# 6. Launch Firefox and Login
echo "Launching Firefox..."
pkill -f firefox || true
# Clean profile slightly
rm -rf /home/ga/.mozilla/firefox/*.default-release/storage/default/https+++localhost* 2>/dev/null || true

nohup firefox "${HR_URL}" >/dev/null 2>&1 &

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        break
    fi
    sleep 1
done

# Focus and Login
focus_firefox
navigate_firefox_to "${HR_URL}/#/login"
sleep 5
DISPLAY=:1 xdotool type "hradmin"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type "test"
DISPLAY=:1 xdotool key Return
sleep 5

# Navigate to Labs section to preload list
navigate_firefox_to "${HR_URL}/#/labs"
sleep 5

# Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="