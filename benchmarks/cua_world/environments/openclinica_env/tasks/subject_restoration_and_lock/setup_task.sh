#!/bin/bash
echo "=== Setting up subject_restoration_and_lock task ==="

source /workspace/scripts/task_utils.sh

# 1. Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Ensure "Baseline Assessment" event definition exists
BASELINE_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3")
if [ "$BASELINE_EXISTS" = "0" ] || [ -z "$BASELINE_EXISTS" ]; then
    echo "Adding Baseline Assessment event definition to DM Trial..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASELINE', 1)"
fi
SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
echo "Baseline Assessment SED_ID: $SED_ID"

# 3. Ensure DM-101 exists as a collateral check subject (Available status, Completed event)
DM101_SUBJ_EXISTS=$(oc_query "SELECT COUNT(*) FROM subject WHERE unique_identifier = 'DM-101-UID'")
if [ "$DM101_SUBJ_EXISTS" = "0" ]; then
    oc_query "INSERT INTO subject (date_of_birth, gender, status_id, unique_identifier, owner_id, date_created) VALUES ('1968-03-22', 'f', 1, 'DM-101-UID', 1, NOW())"
fi
SUBJ101_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'DM-101-UID' LIMIT 1")

DM101_SS_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID")
if [ "$DM101_SS_EXISTS" = "0" ]; then
    oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, owner_id, date_created) VALUES ('DM-101', $SUBJ101_ID, $DM_STUDY_ID, 1, NOW(), 1, NOW())"
fi
SS101_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
# Ensure DM-101 is explicitly Available (1)
oc_query "UPDATE study_subject SET status_id = 1 WHERE study_subject_id = $SS101_ID"

# Ensure DM-101 has a Baseline event
DM101_EV_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event WHERE study_subject_id = $SS101_ID AND study_event_definition_id = $SED_ID")
if [ "$DM101_EV_EXISTS" = "0" ]; then
    oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, subject_event_status_id, start_date, owner_id, date_created) VALUES ($SS101_ID, $SED_ID, 4, NOW(), 1, NOW())"
fi
# Ensure DM-101 event is Completed (4)
oc_query "UPDATE study_event SET subject_event_status_id = 4 WHERE study_subject_id = $SS101_ID AND study_event_definition_id = $SED_ID"


# 4. Set up DM-105 (The target subject)
DM105_SUBJ_EXISTS=$(oc_query "SELECT COUNT(*) FROM subject WHERE unique_identifier = 'DM-105-UID'")
if [ "$DM105_SUBJ_EXISTS" = "0" ]; then
    oc_query "INSERT INTO subject (date_of_birth, gender, status_id, unique_identifier, owner_id, date_created) VALUES ('1982-04-12', 'm', 1, 'DM-105-UID', 1, NOW())"
fi
SUBJ105_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'DM-105-UID' LIMIT 1")

DM105_SS_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID")
if [ "$DM105_SS_EXISTS" = "0" ]; then
    oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, owner_id, date_created) VALUES ('DM-105', $SUBJ105_ID, $DM_STUDY_ID, 5, NOW(), 1, NOW())"
fi
SS105_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID LIMIT 1")

# Force DM-105 into 'Removed' status (5)
oc_query "UPDATE study_subject SET status_id = 5 WHERE study_subject_id = $SS105_ID"

# Ensure DM-105 has a Baseline event
DM105_EV_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event WHERE study_subject_id = $SS105_ID AND study_event_definition_id = $SED_ID")
if [ "$DM105_EV_EXISTS" = "0" ]; then
    oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, subject_event_status_id, start_date, owner_id, date_created) VALUES ($SS105_ID, $SED_ID, 4, NOW(), 1, NOW())"
fi
# Force DM-105's event into 'Completed' status (4)
oc_query "UPDATE study_event SET subject_event_status_id = 4 WHERE study_subject_id = $SS105_ID AND study_event_definition_id = $SED_ID"

echo "Setup complete: DM-105 is Removed (status=5) with a Completed event (status=4)."

# 5. Record Baseline Data for anti-gaming & verification
date +%s > /tmp/task_start_timestamp

AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# 6. UI Setup
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 2

take_screenshot /tmp/task_start_screenshot.png

echo "=== subject_restoration_and_lock setup complete ==="