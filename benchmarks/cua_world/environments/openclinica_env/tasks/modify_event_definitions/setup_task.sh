#!/bin/bash
echo "=== Setting up modify_event_definitions task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- Get DM Trial study_id ---
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial (DM-TRIAL-2024) not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"
echo "$DM_STUDY_ID" > /tmp/dm_study_id.txt

# --- Ensure Study is Available ---
oc_query "UPDATE study SET status_id = 1 WHERE study_id = $DM_STUDY_ID"

# --- Clean existing event definitions for a deterministic state ---
echo "Cleaning existing event definitions for DM Trial..."
# Cascade delete dependencies first to avoid foreign key violations
oc_query "DELETE FROM item_data WHERE event_crf_id IN (SELECT event_crf_id FROM event_crf WHERE study_event_id IN (SELECT study_event_id FROM study_event WHERE study_subject_id IN (SELECT study_subject_id FROM study_subject WHERE study_id=$DM_STUDY_ID)))" 2>/dev/null || true
oc_query "DELETE FROM event_crf WHERE study_event_id IN (SELECT study_event_id FROM study_event WHERE study_subject_id IN (SELECT study_subject_id FROM study_subject WHERE study_id=$DM_STUDY_ID))" 2>/dev/null || true
oc_query "DELETE FROM study_event WHERE study_subject_id IN (SELECT study_subject_id FROM study_subject WHERE study_id=$DM_STUDY_ID)" 2>/dev/null || true
oc_query "DELETE FROM event_definition_crf WHERE study_event_definition_id IN (SELECT study_event_definition_id FROM study_event_definition WHERE study_id=$DM_STUDY_ID)" 2>/dev/null || true
oc_query "DELETE FROM study_event_definition WHERE study_id=$DM_STUDY_ID" 2>/dev/null || true

# --- Create Baseline Event Definitions ---
echo "Creating baseline event definitions..."

# 1. Baseline Assessment
oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, category, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Initial assessment at enrollment', false, 'scheduled', 'Enrollment', 1, 1, NOW(), 'SE_BASELINE', 1)"

# 2. Week 4 Follow-up
oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, category, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Week 4 Follow-up', 'Follow-up visit at week 4', false, 'scheduled', 'Treatment', 1, 1, NOW(), 'SE_WEEK4', 2)"

# 3. Adverse Event Report
oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, category, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Adverse Event Report', 'Unscheduled adverse event capture', true, 'unscheduled', 'Safety', 1, 1, NOW(), 'SE_AE', 3)"

# 4. End of Treatment
oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, category, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'End of Treatment', 'Final treatment visit', false, 'scheduled', '', 1, 1, NOW(), 'SE_EOT', 4)"

# --- Retrieve and Save IDs (to reliably query them later even if renamed) ---
ID_BL=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id=$DM_STUDY_ID AND oc_oid='SE_BASELINE' LIMIT 1")
ID_W4=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id=$DM_STUDY_ID AND oc_oid='SE_WEEK4' LIMIT 1")
ID_AE=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id=$DM_STUDY_ID AND oc_oid='SE_AE' LIMIT 1")
ID_EOT=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id=$DM_STUDY_ID AND oc_oid='SE_EOT' LIMIT 1")

echo "$ID_BL" > /tmp/sed_id_bl.txt
echo "$ID_W4" > /tmp/sed_id_w4.txt
echo "$ID_AE" > /tmp/sed_id_ae.txt
echo "$ID_EOT" > /tmp/sed_id_eot.txt

# --- Record Audit Baseline ---
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count.txt

# --- Set up Web UI State ---
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# --- Anti-gaming Nonce ---
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="