#!/bin/bash
echo "=== Setting up site_operations task ==="

source /workspace/scripts/task_utils.sh

# 1. Resolve parent study ID
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
if [ -z "$CV_STUDY_ID" ]; then
    echo "ERROR: Cardiovascular Outcomes Registry not found in database"
    exit 1
fi
echo "Parent CV Registry study_id: $CV_STUDY_ID"

# 2. Ensure Boston Heart Institute site exists
SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-BHI-001' AND parent_study_id = $CV_STUDY_ID AND status_id != 3 LIMIT 1")
if [ -z "$SITE_ID" ]; then
    echo "Creating Boston Heart Institute site..."
    oc_query "INSERT INTO study (parent_study_id, name, unique_identifier, status_id, owner_id, principal_investigator, date_created, oc_oid) 
              VALUES ($CV_STUDY_ID, 'Boston Heart Institute', 'CV-BHI-001', 1, 1, 'Dr. Michael Rivera', NOW(), 'S_CVBHI001')"
    SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-BHI-001' LIMIT 1")
fi
echo "Site study_id: $SITE_ID"

# 3. Ensure "Screening Visit" event definition exists on PARENT study
SCREENING_SED=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Screening Visit' AND study_id = $CV_STUDY_ID AND status_id != 3 LIMIT 1")
if [ -z "$SCREENING_SED" ]; then
    echo "Creating Screening Visit event definition..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) 
              VALUES ($CV_STUDY_ID, 'Screening Visit', 'Initial patient screening', false, 'Scheduled', 1, 1, NOW(), 'SE_SCREEN', 1)"
fi

# 4. Clean up existing subjects (CV-201, CV-202) from both parent and site
echo "Cleaning up any pre-existing subject records..."
for SUBJ_LABEL in "CV-201" "CV-202"; do
    SS_IDS=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ_LABEL' AND (study_id = $CV_STUDY_ID OR study_id = $SITE_ID)")
    for SS_ID in $SS_IDS; do
        if [ -n "$SS_ID" ]; then
            SUBJ_ID=$(oc_query "SELECT subject_id FROM study_subject WHERE study_subject_id = $SS_ID LIMIT 1")
            oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true
            oc_query "DELETE FROM study_subject WHERE study_subject_id = $SS_ID" 2>/dev/null || true
            if [ -n "$SUBJ_ID" ]; then
                oc_query "DELETE FROM subject WHERE subject_id = $SUBJ_ID" 2>/dev/null || true
            fi
        fi
    done
done

# 5. Ensure mrivera exists and clean up site roles
MRIVERA_EXISTS=$(oc_query "SELECT COUNT(*) FROM user_account WHERE user_name = 'mrivera'")
if [ "$MRIVERA_EXISTS" = "0" ]; then
    echo "Creating mrivera user account..."
    oc_query "INSERT INTO user_account (user_name, passwd, first_name, last_name, email, status_id, owner_id, date_created) 
              VALUES ('mrivera', 'da39a3ee5e6b4b0d3255bfef95601890afd80709', 'Maria', 'Rivera', 'mrivera@clinical.org', 1, 1, NOW())"
fi
echo "Cleaning up mrivera site-level roles..."
oc_query "DELETE FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $SITE_ID" 2>/dev/null || true

# 6. Set baseline references
date +%s > /tmp/task_start_timestamp
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
generate_result_nonce > /tmp/result_nonce
echo "Audit baseline: ${AUDIT_BASELINE:-0}, Nonce generated."

# 7. Start application, log in, navigate to PARENT study (agent must switch to site)
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "CV-REG-2023"
focus_firefox
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== site_operations setup complete ==="