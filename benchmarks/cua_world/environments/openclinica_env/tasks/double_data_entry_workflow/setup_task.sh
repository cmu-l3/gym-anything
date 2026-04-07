#!/bin/bash
echo "=== Setting up double_data_entry_workflow task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_timestamp

# Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 1. Clean up existing Vital Signs CRF for clean state
EXISTING_CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE LOWER(TRIM(name)) = 'vital signs' LIMIT 1")
if [ -n "$EXISTING_CRF_ID" ]; then
    echo "Found existing Vital Signs CRF. Cleaning up..."
    oc_query "DELETE FROM item_data WHERE event_crf_id IN (SELECT ec.event_crf_id FROM event_crf ec JOIN crf_version cv ON ec.crf_version_id = cv.crf_version_id WHERE cv.crf_id = $EXISTING_CRF_ID)" 2>/dev/null || true
    oc_query "DELETE FROM event_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID)" 2>/dev/null || true
    oc_query "DELETE FROM event_definition_crf WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    oc_query "DELETE FROM event_definition_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID)" 2>/dev/null || true
    oc_query "DELETE FROM item_form_metadata WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID)" 2>/dev/null || true
    oc_query "DELETE FROM crf_version WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    oc_query "DELETE FROM crf WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    echo "CRF Cleanup complete."
fi

# 2. Ensure Event Definition exists
BASELINE_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3")
if [ "$BASELINE_EXISTS" = "0" ] || [ -z "$BASELINE_EXISTS" ]; then
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASELINE', 1)"
fi

# 3. Ensure DM-101 exists and clear their events
DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -n "$DM101_SS_ID" ]; then
    echo "Clearing existing events for DM-101..."
    oc_query "DELETE FROM item_data WHERE event_crf_id IN (SELECT event_crf_id FROM event_crf WHERE study_event_id IN (SELECT study_event_id FROM study_event WHERE study_subject_id = $DM101_SS_ID))" 2>/dev/null || true
    oc_query "DELETE FROM event_crf WHERE study_event_id IN (SELECT study_event_id FROM study_event WHERE study_subject_id = $DM101_SS_ID)" 2>/dev/null || true
    oc_query "DELETE FROM study_event WHERE study_subject_id = $DM101_SS_ID" 2>/dev/null || true
fi

# 4. Create dep1 and dep2 users
for USERNAME in dep1 dep2; do
    EXISTS=$(oc_query "SELECT COUNT(*) FROM user_account WHERE user_name = '$USERNAME'")
    if [ "$EXISTS" = "0" ]; then
        # Password 'Admin123!' hashed via SHA1 for OpenClinica
        oc_query "INSERT INTO user_account (user_name, passwd, first_name, last_name, email, status_id, owner_id, date_created, account_non_locked, passwd_timestamp) VALUES ('$USERNAME', '664819d8c5343676c9225b5ed00a5cdc6f3a1ff3', 'Data', 'Entry', '$USERNAME@clinical.org', 1, 1, NOW(), true, CURRENT_DATE + INTERVAL '365 days')"
    fi
    # Assign data entry role
    ROLE_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_user_role WHERE user_name = '$USERNAME' AND study_id = $DM_STUDY_ID")
    if [ "$ROLE_EXISTS" = "0" ]; then
        oc_query "INSERT INTO study_user_role (role_name, study_id, status_id, owner_id, date_created, user_name) VALUES ('data_entry_person', $DM_STUDY_ID, 1, 1, NOW(), '$USERNAME')"
    fi
done
echo "Data entry accounts dep1 and dep2 provisioned."

# 5. Place CRF file
if [ -f "/workspace/data/sample_crf.xls" ]; then
    cp /workspace/data/sample_crf.xls /home/ga/vital_signs_crf.xls
    chown ga:ga /home/ga/vital_signs_crf.xls
    chmod 644 /home/ga/vital_signs_crf.xls
fi

# 6. Record Audits & Nonce
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
NONCE=$(generate_result_nonce)
echo "Nonce generated."

# 7. Start Firefox & Login
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="