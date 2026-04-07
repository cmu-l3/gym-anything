#!/bin/bash
echo "=== Setting up site_closeout_and_archival task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure the parent study exists
PARENT_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
if [ -z "$PARENT_ID" ]; then
    echo "ERROR: Parent study Cardiovascular Outcomes Registry (CV-REG-2023) not found."
    exit 1
fi
echo "Parent study ID: $PARENT_ID"

# 2. Ensure Boston Heart Institute site exists
SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-BHI-001' AND status_id != 3 LIMIT 1")
if [ -z "$SITE_ID" ]; then
    echo "Creating Boston Heart Institute site..."
    oc_query "INSERT INTO study (name, unique_identifier, parent_study_id, status_id, owner_id, date_created, protocol_type, expected_total_enrollment)
              VALUES ('Boston Heart Institute', 'CV-BHI-001', $PARENT_ID, 1, 1, NOW(), 'observational', 50)"
    SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-BHI-001' AND status_id != 3 LIMIT 1")
else
    # Ensure it's active (Available) for the task
    oc_query "UPDATE study SET status_id = 1 WHERE study_id = $SITE_ID"
fi
echo "Site ID: $SITE_ID"

# 3. Ensure subjects CV-BHI-101 and CV-BHI-102 exist at the site
for idx in 101 102; do
    LABEL="CV-BHI-$idx"
    DOB="1955-04-12"
    GENDER="m"
    if [ "$idx" == "102" ]; then
        DOB="1960-08-22"
        GENDER="f"
    fi

    SS_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE label = '$LABEL' AND study_id = $SITE_ID AND status_id != 3")
    if [ "$SS_EXISTS" -eq 0 ]; then
        echo "Creating subject $LABEL..."
        oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created) VALUES ('$DOB', '$GENDER', 1, 1, NOW())"
        NEW_SUBJ_ID=$(oc_query "SELECT subject_id FROM subject ORDER BY subject_id DESC LIMIT 1")
        oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date) VALUES ('$LABEL', $NEW_SUBJ_ID, $SITE_ID, 1, 1, NOW(), CURRENT_DATE - INTERVAL '100 days')"
    else
        oc_query "UPDATE study_subject SET status_id = 1 WHERE label = '$LABEL' AND study_id = $SITE_ID"
    fi
done

# 4. Clean up any existing output files to prevent gaming
rm -f /home/ga/Documents/CV-BHI-101_Casebook.pdf 2>/dev/null || true
rm -f /home/ga/Documents/CV-BHI-102_Casebook.pdf 2>/dev/null || true
rm -f /home/ga/Documents/BHI_Site_Data.xml 2>/dev/null || true

# 5. Record Baseline Metrics
echo "Recording baseline states..."
date +%s > /tmp/task_start_timestamp

AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# 6. Ensure OpenClinica is running and user is logged in
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

echo "=== site_closeout_and_archival setup complete ==="