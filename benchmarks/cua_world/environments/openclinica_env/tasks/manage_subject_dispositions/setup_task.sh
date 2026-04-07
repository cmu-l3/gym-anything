#!/bin/bash
echo "=== Setting up manage_subject_dispositions task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Resolve study_id for DM-TRIAL-2024
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial (DM-TRIAL-2024) not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Ensure all five subjects exist in the database
SUBJECTS=("DM-101" "DM-102" "DM-103" "DM-104" "DM-105")
for label in "${SUBJECTS[@]}"; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$label' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$SS_ID" ]; then
        echo "Creating missing subject $label..."
        # Insert base subject record
        oc_query "INSERT INTO subject (date_of_birth, gender, status_id) VALUES ('1970-01-01', 'm', 1)"
        SUBJ_ID=$(oc_query "SELECT MAX(subject_id) FROM subject")
        # Insert study_subject linkage
        OID_SUFFIX=$(echo "$label" | tr -d '-')
        oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, oc_oid) VALUES ('$label', $SUBJ_ID, $DM_STUDY_ID, 1, NOW(), 'SS_$OID_SUFFIX')"
    fi
done

# 3. Set exact initial statuses
echo "Setting initial subject statuses..."
oc_query "UPDATE study_subject SET status_id = 1 WHERE label IN ('DM-101', 'DM-102', 'DM-103', 'DM-105') AND study_id = $DM_STUDY_ID"
oc_query "UPDATE study_subject SET status_id = 5 WHERE label = 'DM-104' AND study_id = $DM_STUDY_ID"

# 4. Record baseline audit log count
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline: ${AUDIT_BASELINE:-0}"

# 5. Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Generated nonce: $NONCE"

# 6. Open Firefox and log in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# 7. Take initial state screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="