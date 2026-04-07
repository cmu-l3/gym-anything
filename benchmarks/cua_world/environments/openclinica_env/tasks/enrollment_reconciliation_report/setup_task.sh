#!/bin/bash
echo "=== Setting up enrollment_reconciliation_report task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Get DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 1. Ensure Subjects Exist
echo "Ensuring all required subjects exist..."
SUBJECTS=(
    "DM-104|m|1945-09-30|1"
    "DM-105|f|1973-06-12|3"
)

for subj in "${SUBJECTS[@]}"; do
    LABEL=$(echo "$subj" | cut -d'|' -f1)
    GENDER=$(echo "$subj" | cut -d'|' -f2)
    DOB=$(echo "$subj" | cut -d'|' -f3)
    STATUS=$(echo "$subj" | cut -d'|' -f4)
    
    # Check if exists
    EXISTS=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$EXISTS" ]; then
        echo "Creating subject $LABEL..."
        # Create subject
        oc_query "INSERT INTO subject (date_of_birth, gender, unique_identifier, status_id, owner_id, date_created) VALUES ('$DOB', '$GENDER', '$LABEL', 1, 1, NOW())"
        SUBJ_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = '$LABEL' ORDER BY subject_id DESC LIMIT 1")
        
        # Link to study
        if [ -n "$SUBJ_ID" ]; then
            oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date) VALUES ('$LABEL', $SUBJ_ID, $DM_STUDY_ID, $STATUS, 1, NOW(), CURRENT_DATE)"
        fi
    else
        # Update status if needed
        oc_query "UPDATE study_subject SET status_id = $STATUS WHERE study_subject_id = $EXISTS"
    fi
done

# Ensure DM-101, DM-102, DM-103 are active (status_id=1)
for LABEL in DM-101 DM-102 DM-103; do
    oc_query "UPDATE study_subject SET status_id = 1 WHERE label = '$LABEL' AND study_id = $DM_STUDY_ID"
done

# 2. Ensure Event Definitions Exist
echo "Ensuring all required event definitions exist..."
EVENTS=(
    "Screening Visit|Scheduled|false"
    "Baseline Assessment|Scheduled|false"
    "Week 4 Follow-up|Scheduled|true"
)

for ev in "${EVENTS[@]}"; do
    NAME=$(echo "$ev" | cut -d'|' -f1)
    TYPE=$(echo "$ev" | cut -d'|' -f2)
    REPEATING=$(echo "$ev" | cut -d'|' -f3)
    
    EXISTS=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = '$NAME' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
    if [ -z "$EXISTS" ]; then
        echo "Creating event definition $NAME..."
        oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid) VALUES ($DM_STUDY_ID, '$NAME', 'Study Visit', $REPEATING, '$TYPE', 1, 1, NOW(), 'SE_DM_${NAME// /}')"
    fi
done

# 3. Ensure Users and Roles Exist
echo "Ensuring users and roles exist..."
# Ensure mrivera and lchang accounts
oc_query "INSERT INTO user_account (user_name, passwd, first_name, last_name, email, status_id, owner_id, date_created) SELECT 'mrivera', 'hash', 'Michael', 'Rivera', 'm@test.com', 1, 1, NOW() WHERE NOT EXISTS (SELECT 1 FROM user_account WHERE user_name='mrivera')" 2>/dev/null || true
oc_query "INSERT INTO user_account (user_name, passwd, first_name, last_name, email, status_id, owner_id, date_created) SELECT 'lchang', 'hash', 'Linda', 'Chang', 'l@test.com', 1, 1, NOW() WHERE NOT EXISTS (SELECT 1 FROM user_account WHERE user_name='lchang')" 2>/dev/null || true

# Assign roles to DM-TRIAL-2024
oc_query "DELETE FROM study_user_role WHERE study_id = $DM_STUDY_ID AND user_name IN ('mrivera', 'lchang')"
oc_query "INSERT INTO study_user_role (role_name, study_id, status_id, owner_id, date_created, user_name) VALUES ('data_manager', $DM_STUDY_ID, 1, 1, NOW(), 'mrivera')"
oc_query "INSERT INTO study_user_role (role_name, study_id, status_id, owner_id, date_created, user_name) VALUES ('monitor', $DM_STUDY_ID, 1, 1, NOW(), 'lchang')"

# 4. Cleanup environment
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/enrollment_reconciliation.txt
chown -R ga:ga /home/ga/Documents

# 5. UI Setup
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# 6. Audit logging baseline
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="