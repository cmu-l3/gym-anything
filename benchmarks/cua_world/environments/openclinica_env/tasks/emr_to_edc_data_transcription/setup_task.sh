#!/bin/bash
echo "=== Setting up EMR Transcription Task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare EMR Data File
mkdir -p /home/ga/data
cat << 'EOF' > /home/ga/data/emr_export_jsmith.txt
PATIENT ENCOUNTER SUMMARY
-------------------------
Patient Name: John Smith
DOB: 1965-08-22
Sex: Male
Encounter Date: 2024-05-14

VITALS (Triage)
---------------
Heart Rate: 82 bpm
Blood Pressure: 145 / 92 mmHg
Height: 70 inches
Weight: 195 lbs

Notes: Patient presents for baseline registry evaluation.
EOF
chown -R ga:ga /home/ga/data
chmod 644 /home/ga/data/emr_export_jsmith.txt

# 2. Provide CRF Template
if [ -f "/workspace/data/sample_crf.xls" ]; then
    cp /workspace/data/sample_crf.xls /home/ga/data/vitals_template.xls
    chown ga:ga /home/ga/data/vitals_template.xls
    chmod 644 /home/ga/data/vitals_template.xls
else
    echo "WARNING: /workspace/data/sample_crf.xls not found, agent may lack template."
fi

# 3. Ensure Study and Event Definition
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
if [ -z "$CV_STUDY_ID" ]; then
    echo "ERROR: Cardiovascular Outcomes Registry not found!"
    exit 1
fi

BE_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $CV_STUDY_ID AND name = 'Baseline Encounter' AND status_id != 3")
if [ "$BE_EXISTS" = "0" ] || [ -z "$BE_EXISTS" ]; then
    echo "Creating Baseline Encounter event definition..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($CV_STUDY_ID, 'Baseline Encounter', 'Initial clinical evaluation', false, 'Scheduled', 1, 1, NOW(), 'SE_CV_BASELINE', 1)"
fi

# 4. Clean up target subject (CV-106) for a fresh state
CV106_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'CV-106' AND study_id = $CV_STUDY_ID LIMIT 1")
if [ -n "$CV106_SS_ID" ]; then
    echo "Removing existing CV-106 to ensure clean state..."
    oc_query "DELETE FROM study_event WHERE study_subject_id = $CV106_SS_ID" 2>/dev/null || true
    SUBJ_ID=$(oc_query "SELECT subject_id FROM study_subject WHERE study_subject_id = $CV106_SS_ID LIMIT 1")
    oc_query "DELETE FROM study_subject WHERE study_subject_id = $CV106_SS_ID" 2>/dev/null || true
    if [ -n "$SUBJ_ID" ]; then
        oc_query "DELETE FROM subject WHERE subject_id = $SUBJ_ID" 2>/dev/null || true
    fi
fi

# 5. Timestamp and Desktop Prep
date +%s > /tmp/task_start_timestamp

if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "CV-REG-2023"
focus_firefox

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup Complete ==="