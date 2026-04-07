#!/bin/bash
echo "=== Setting up export_audit_materials task ==="

source /workspace/scripts/task_utils.sh

# Remove target directory if it exists to ensure a clean state
rm -rf /home/ga/Documents/Audit_Materials 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Get DM Trial study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# Ensure subjects DM-101 and DM-102 exist for the casebook export
for SUBJ in "DM-101" "DM-102"; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$SS_ID" ]; then
        echo "Creating missing subject $SUBJ..."
        oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created) VALUES ('1970-01-01', 'm', 1, 1, NOW())"
        SUBJ_ID=$(oc_query "SELECT subject_id FROM subject ORDER BY subject_id DESC LIMIT 1")
        oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date) VALUES ('$SUBJ', $SUBJ_ID, $DM_STUDY_ID, 1, 1, NOW(), NOW())"
    fi
done

# Ensure Demographics CRF exists for the Annotated CRF export
CRF_EXISTS=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Demographics' LIMIT 1")
if [ -z "$CRF_EXISTS" ]; then
    echo "Creating Demographics CRF..."
    oc_query "INSERT INTO crf (status_id, name, description, owner_id, date_created, source_study_id, oc_oid) VALUES (1, 'Demographics', 'Demographics CRF', 1, NOW(), 1, 'F_DEMOGRAPHICS')"
    NEW_CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Demographics' LIMIT 1")
    if [ -n "$NEW_CRF_ID" ]; then
        oc_query "INSERT INTO crf_version (crf_id, name, description, revision_notes, status_id, owner_id, date_created, oc_oid) VALUES ($NEW_CRF_ID, 'v1.0', 'Initial version', 'Created for audit', 1, 1, NOW(), 'F_DEMOGRAPHICS_V10')"
    fi
fi

# Set marker for time comparison to detect files created during task execution
touch /tmp/task_start_timestamp
sleep 1

# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox

# Final maximize and screenshot
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="