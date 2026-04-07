#!/bin/bash
echo "=== Setting up archival_casebook_generation task ==="

source /workspace/scripts/task_utils.sh

# Ensure CV-REG-2023 exists
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")

if [ -z "$CV_STUDY_ID" ]; then
    echo "ERROR: CV-REG-2023 not found"
    exit 1
fi

# Ensure CV-101 exists
CV101_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE label = 'CV-101' AND study_id = $CV_STUDY_ID")
if [ "$CV101_EXISTS" = "0" ] || [ -z "$CV101_EXISTS" ]; then
    echo "Creating subject CV-101..."
    oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created) VALUES ('1960-05-12', 'm', 1, 1, NOW())"
    SUBJ_ID=$(oc_query "SELECT subject_id FROM subject ORDER BY subject_id DESC LIMIT 1")
    oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, owner_id, date_created) VALUES ('CV-101', $SUBJ_ID, $CV_STUDY_ID, 1, NOW(), 1, NOW())"
fi

# Clean up any existing PDFs
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
rm -f /home/ga/Documents/CV-101_Casebook.pdf 2>/dev/null || true
rm -f /tmp/agent_casebook.pdf 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_timestamp

# Ensure Firefox running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "CV-REG-2023"
focus_firefox
sleep 1

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="