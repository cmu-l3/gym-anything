#!/bin/bash
echo "=== Setting up manage_repeating_visit_cycles task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# Add "Week 4 Follow-up" event definition if it doesn't exist
WEEK4_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Week 4 Follow-up' AND status_id != 3")
if [ "$WEEK4_EXISTS" = "0" ] || [ -z "$WEEK4_EXISTS" ]; then
    echo "Adding Week 4 Follow-up event definition to DM Trial..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Week 4 Follow-up', 'Four-week follow-up visit for safety and efficacy assessment', true, 'Scheduled', 1, 1, NOW(), 'SE_DM_WEEK4', 2)"
else
    echo "Week 4 Follow-up event definition already exists"
    # Ensure it's correctly marked as repeating (crucial for this task)
    oc_query "UPDATE study_event_definition SET repeating = true WHERE study_id = $DM_STUDY_ID AND name = 'Week 4 Follow-up'"
fi

WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
echo "Week 4 Follow-up SED id: $WEEK4_SED_ID"

# Get Subject DM-101 study_subject_id
DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -z "$DM101_SS_ID" ]; then
    echo "ERROR: Subject DM-101 not found"
    exit 1
fi
echo "DM-101 study_subject_id: $DM101_SS_ID"

# Clean up any existing events for DM-101 under this definition for a clean state
echo "Cleaning up pre-existing Week 4 Follow-up events for DM-101..."
oc_query "DELETE FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $WEEK4_SED_ID" 2>/dev/null || true

# Seed Cycle 1 (sample_ordinal = 1) for DM-101
echo "Seeding Cycle 1 (occurrence 1) for DM-101..."
oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, sample_ordinal, date_start, status_id, owner_id, date_created, subject_event_status_id) VALUES ($DM101_SS_ID, $WEEK4_SED_ID, 1, '2024-03-18', 1, 1, NOW(), 1)" 2>/dev/null || true
echo "Cycle 1 seeded with date 2024-03-18."

# Verify seeding
SEEDED_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $WEEK4_SED_ID")
echo "Total seeded occurrences: $SEEDED_COUNT (Should be 1)"

# Generate a nonce for result integrity
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# Baseline audit log
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

# Start and configure browser
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

echo "=== manage_repeating_visit_cycles setup complete ==="