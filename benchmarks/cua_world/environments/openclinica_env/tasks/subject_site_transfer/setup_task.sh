#!/bin/bash
echo "=== Setting up subject_site_transfer task ==="

source /workspace/scripts/task_utils.sh

# 1. Get the Parent Study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Ensure both sites exist
for SITE_NAME in "Boston Clinic" "New York Hub"; do
    if [ "$SITE_NAME" == "Boston Clinic" ]; then UID="DM-BOS-01"; else UID="DM-NY-02"; fi
    EXISTS=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = '$UID' AND status_id != 3 LIMIT 1")
    if [ -z "$EXISTS" ]; then
        echo "Creating site: $SITE_NAME ($UID)..."
        OID="S_${UID//-/_}"
        oc_query "INSERT INTO study (name, unique_identifier, parent_study_id, status_id, owner_id, date_created, protocol_type, principal_investigator, oc_oid) VALUES ('$SITE_NAME', '$UID', $DM_STUDY_ID, 1, 1, NOW(), 'interventional', 'Dr. Site', '$OID')"
    fi
done

# 3. Retrieve site IDs
BOS_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-BOS-01' AND status_id != 3 LIMIT 1")
NY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-NY-02' AND status_id != 3 LIMIT 1")
echo "Boston Clinic ID: $BOS_ID"
echo "New York Hub ID: $NY_ID"

# Save site IDs for export verification
echo "$BOS_ID" > /tmp/bos_site_id
echo "$NY_ID" > /tmp/ny_site_id

# 4. Clean up any existing DM-105 records to ensure a pristine start state
echo "Cleaning up any existing DM-105 records..."
DM105_SS_IDS=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105'")
for SS_ID in $DM105_SS_IDS; do
    oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true
    oc_query "DELETE FROM study_subject WHERE study_subject_id = $SS_ID" 2>/dev/null || true
done

# 5. Ensure the base demographic subject exists
SUBJ_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'UID-DM-105' LIMIT 1")
if [ -z "$SUBJ_ID" ]; then
    echo "Creating base subject record for DM-105..."
    oc_query "INSERT INTO subject (date_of_birth, gender, unique_identifier, status_id, owner_id, date_created) VALUES ('1982-05-15', 'm', 'UID-DM-105', 1, 1, NOW())"
    SUBJ_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'UID-DM-105' LIMIT 1")
else
    echo "Base subject record exists, resetting demographics..."
    oc_query "UPDATE subject SET date_of_birth='1982-05-15', gender='m' WHERE subject_id=$SUBJ_ID"
fi

# 6. Assign DM-105 to Boston Clinic initially
echo "Assigning DM-105 to Boston Clinic site..."
oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, owner_id, date_created, oc_oid) VALUES ('DM-105', $SUBJ_ID, $BOS_ID, 1, CURRENT_DATE, 1, NOW(), 'SS_DM105_BOS')"

# 7. Record baseline audit log to detect GUI bypass
AUDIT_BASELINE=$(oc_query "SELECT COUNT(*) FROM audit_log_event")
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline: ${AUDIT_BASELINE:-0}"

# 8. Setup browser and navigate
date +%s > /tmp/task_start_timestamp
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Use robust navigation tools from task_utils.sh
wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

take_screenshot /tmp/task_start_screenshot.png

echo "=== subject_site_transfer setup complete ==="