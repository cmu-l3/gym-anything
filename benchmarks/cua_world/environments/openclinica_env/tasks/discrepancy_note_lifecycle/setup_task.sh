#!/bin/bash
echo "=== Setting up discrepancy_note_lifecycle task ==="

source /workspace/scripts/task_utils.sh

# Get DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# Ensure subjects exist
for SUBJ_LABEL in DM-101 DM-102 DM-103; do
    SS_CHECK=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ_LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$SS_CHECK" ]; then
        echo "WARNING: Subject $SUBJ_LABEL not found in DM Trial"
    fi
done

# Clean up any existing discrepancy notes on DM-101, DM-102, DM-103 to start fresh
for SUBJ_LABEL in DM-101 DM-102 DM-103; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ_LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -n "$SS_ID" ]; then
        # Find notes linked to this subject via dn_study_subject_map
        DN_IDS=$(oc_query "SELECT discrepancy_note_id FROM dn_study_subject_map WHERE study_subject_id = $SS_ID")
        for DN_ID in $DN_IDS; do
            if [ -n "$DN_ID" ]; then
                oc_query "DELETE FROM dn_study_subject_map WHERE discrepancy_note_id = $DN_ID" 2>/dev/null || true
                oc_query "DELETE FROM discrepancy_note WHERE discrepancy_note_id = $DN_ID" 2>/dev/null || true
                oc_query "DELETE FROM discrepancy_note WHERE parent_dn_id = $DN_ID" 2>/dev/null || true
            fi
        done
    fi
done

# Create pre-existing discrepancy note on DM-103
DM103_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-103' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -n "$DM103_SS_ID" ]; then
    echo "Creating pre-existing query on DM-103..."
    # Insert parent note (Resolution Proposed = 3, Type = Query = 3)
    oc_query "INSERT INTO discrepancy_note (description, discrepancy_note_type_id, resolution_status_id, detailed_notes, date_created, owner_id, study_id) VALUES ('Blood pressure value appears unusually high. Site to verify against source documentation.', 3, 3, 'Pre-existing query for task', NOW(), 1, $DM_STUDY_ID)"
    
    # Get the ID of the note we just inserted
    DN_ID=$(oc_query "SELECT discrepancy_note_id FROM discrepancy_note WHERE description LIKE 'Blood pressure value appears unusually high%' AND study_id = $DM_STUDY_ID ORDER BY discrepancy_note_id DESC LIMIT 1")
    
    if [ -n "$DN_ID" ]; then
        oc_query "INSERT INTO dn_study_subject_map (discrepancy_note_id, study_subject_id, column_name) VALUES ($DN_ID, $DM103_SS_ID, 'enrollment_date')"
        echo "Pre-existing query created (ID: $DN_ID)"
    fi
fi

# Record baselines
INITIAL_DN_COUNT=$(oc_query "SELECT COUNT(*) FROM discrepancy_note WHERE study_id = $DM_STUDY_ID")
echo "${INITIAL_DN_COUNT:-0}" > /tmp/initial_dn_count.txt

oc_query "SELECT discrepancy_note_id FROM discrepancy_note WHERE study_id = $DM_STUDY_ID" > /tmp/initial_dn_ids.txt

AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count.txt

NONCE=$(generate_result_nonce)
echo "$NONCE" > /tmp/result_nonce

date +%s > /tmp/task_start_timestamp

# Browser setup
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

take_screenshot /tmp/task_start_screenshot.png

echo "=== discrepancy_note_lifecycle setup complete ==="