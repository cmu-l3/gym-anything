#!/bin/bash
echo "=== Setting up build_registry_protocol task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Identify CV-REG-2023 Study ID
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
if [ -z "$CV_STUDY_ID" ]; then
    echo "ERROR: Cardiovascular Outcomes Registry (CV-REG-2023) not found"
    exit 1
fi
echo "CV Registry study_id: $CV_STUDY_ID"
echo "$CV_STUDY_ID" > /tmp/cv_study_id.txt

# 2. Clean up existing data to ensure a completely clean state for the task
echo "Cleaning up pre-existing CV-REG-2023 data..."

# Delete study events and subjects
oc_query "DELETE FROM study_event WHERE study_subject_id IN (SELECT study_subject_id FROM study_subject WHERE study_id = $CV_STUDY_ID)" 2>/dev/null || true
oc_query "DELETE FROM study_subject WHERE study_id = $CV_STUDY_ID" 2>/dev/null || true

# Delete event definitions and their links
oc_query "DELETE FROM event_definition_crf WHERE study_event_definition_id IN (SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $CV_STUDY_ID)" 2>/dev/null || true
oc_query "DELETE FROM study_event_definition WHERE study_id = $CV_STUDY_ID" 2>/dev/null || true

echo "Cleanup complete."

# 3. Record baselines
INITIAL_EVENT_DEF_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $CV_STUDY_ID AND status_id != 3")
INITIAL_SUBJECT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE study_id = $CV_STUDY_ID AND status_id != 3")

echo "${INITIAL_EVENT_DEF_COUNT:-0}" > /tmp/initial_event_def_count.txt
echo "${INITIAL_SUBJECT_COUNT:-0}" > /tmp/initial_subject_count.txt
echo "Initial event definitions: ${INITIAL_EVENT_DEF_COUNT:-0}"
echo "Initial subjects: ${INITIAL_SUBJECT_COUNT:-0}"

# 4. Generate Nonce for Result Integrity
NONCE=$(generate_result_nonce)
echo "Result nonce generated."

# 5. Launch OpenClinica, Login, and Switch Study Context
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "CV-REG-2023"
focus_firefox
sleep 2

# 6. Record audit baseline (to detect direct database manipulation)
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count.txt
echo "Audit log baseline: ${AUDIT_BASELINE:-0}"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="