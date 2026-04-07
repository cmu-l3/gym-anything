#!/bin/bash
echo "=== Setting up remediate_phi_violation task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_timestamp

# --- 1. Find the Parent Study ---
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
if [ -z "$CV_STUDY_ID" ]; then
    echo "ERROR: Cardiovascular Outcomes Registry not found"
    exit 1
fi
echo "Parent Study ID: $CV_STUDY_ID"

# --- 2. Ensure Boston Heart Institute Site Exists ---
oc_query "
INSERT INTO study (parent_study_id, name, unique_identifier, status_id, owner_id, date_created, facility_name)
SELECT $CV_STUDY_ID, 'Boston Heart Institute', 'CV-BHI-001', 1, 1, NOW(), 'Boston Heart Institute'
WHERE NOT EXISTS (SELECT 1 FROM study WHERE unique_identifier = 'CV-BHI-001');
" 2>/dev/null || true

SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-BHI-001' AND status_id != 3 LIMIT 1")
if [ -z "$SITE_ID" ]; then
    echo "ERROR: Failed to create or find Boston Heart Institute site"
    exit 1
fi
echo "Site Study ID: $SITE_ID"

# Reset Facility Name to clean state (remove any previous CAPA ACTIVE flags)
oc_query "UPDATE study SET facility_name = 'Boston Heart Institute' WHERE study_id = $SITE_ID" 2>/dev/null || true

# --- 3. Clean up existing target subjects ---
echo "Cleaning up pre-existing target subjects..."
for LABEL in MRN-84729 MRN-55912 MRN-11048 CV-301 CV-302 CV-303; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$LABEL' LIMIT 1")
    if [ -n "$SS_ID" ]; then
        SUBJ_ID=$(oc_query "SELECT subject_id FROM study_subject WHERE study_subject_id = $SS_ID LIMIT 1")
        oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true
        oc_query "DELETE FROM study_subject WHERE study_subject_id = $SS_ID" 2>/dev/null || true
        if [ -n "$SUBJ_ID" ]; then
            oc_query "DELETE FROM subject WHERE subject_id = $SUBJ_ID" 2>/dev/null || true
        fi
    fi
done

# --- 4. Inject the PHI Violations ---
echo "Injecting PHI violations..."

# Subject 1
oc_query "
WITH new_subj AS (
    INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created)
    VALUES ('1965-04-12', 'm', 1, 1, NOW()) RETURNING subject_id
)
INSERT INTO study_subject (study_id, subject_id, label, secondary_label, status_id, owner_id, date_created, enrollment_date)
SELECT $SITE_ID, subject_id, 'MRN-84729', 'John Doe', 1, 1, NOW(), CURRENT_DATE FROM new_subj;
"

# Subject 2
oc_query "
WITH new_subj AS (
    INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created)
    VALUES ('1972-11-05', 'f', 1, 1, NOW()) RETURNING subject_id
)
INSERT INTO study_subject (study_id, subject_id, label, secondary_label, status_id, owner_id, date_created, enrollment_date)
SELECT $SITE_ID, subject_id, 'MRN-55912', 'Mary Smith', 1, 1, NOW(), CURRENT_DATE FROM new_subj;
"

# Subject 3
oc_query "
WITH new_subj AS (
    INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created)
    VALUES ('1980-08-22', 'm', 1, 1, NOW()) RETURNING subject_id
)
INSERT INTO study_subject (study_id, subject_id, label, secondary_label, status_id, owner_id, date_created, enrollment_date)
SELECT $SITE_ID, subject_id, 'MRN-11048', 'Robert Jones', 1, 1, NOW(), CURRENT_DATE FROM new_subj;
"

# --- 5. Browser Setup and Authentication ---
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "CV-REG-2023" # Set active context to parent study initially
focus_firefox
sleep 1

# --- 6. Security & Anti-Gaming Baselines ---
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline: ${AUDIT_BASELINE:-0}"

NONCE=$(generate_result_nonce)
echo "Generated verification nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="