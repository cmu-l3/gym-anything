#!/bin/bash
echo "=== Setting up add_study_site task ==="

source /workspace/scripts/task_utils.sh

# Get CV Registry study_id
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
if [ -z "$CV_STUDY_ID" ]; then
    echo "ERROR: Cardiovascular Outcomes Registry not found"
    exit 1
fi
echo "CV Registry study_id: $CV_STUDY_ID"

# Clean up any pre-existing sites under CV Registry
EXISTING_SITES=$(oc_query "SELECT study_id FROM study WHERE parent_study_id = $CV_STUDY_ID AND status_id != 3")
if [ -n "$EXISTING_SITES" ]; then
    echo "Removing existing sites from CV Registry for clean state..."
    for SITE_ID in $EXISTING_SITES; do
        # Remove site subjects first
        SITE_SUBJECTS=$(oc_query "SELECT study_subject_id FROM study_subject WHERE study_id = $SITE_ID")
        for SS_ID in $SITE_SUBJECTS; do
            SUBJ_ID=$(oc_query "SELECT subject_id FROM study_subject WHERE study_subject_id = $SS_ID LIMIT 1")
            oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true
            oc_query "DELETE FROM study_subject WHERE study_subject_id = $SS_ID" 2>/dev/null || true
            if [ -n "$SUBJ_ID" ]; then
                oc_query "DELETE FROM subject WHERE subject_id = $SUBJ_ID" 2>/dev/null || true
            fi
        done
        oc_query "DELETE FROM study WHERE study_id = $SITE_ID" 2>/dev/null || true
    done
    echo "Existing sites removed"
fi

# Clean up any pre-existing CV subjects at parent study level
CV_SUBJECTS=$(oc_query "SELECT study_subject_id FROM study_subject WHERE study_id = $CV_STUDY_ID AND label LIKE 'CV-%'")
if [ -n "$CV_SUBJECTS" ]; then
    echo "Removing existing CV subjects for clean state..."
    for SS_ID in $CV_SUBJECTS; do
        SUBJ_ID=$(oc_query "SELECT subject_id FROM study_subject WHERE study_subject_id = $SS_ID LIMIT 1")
        oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true
        oc_query "DELETE FROM study_subject WHERE study_subject_id = $SS_ID" 2>/dev/null || true
        if [ -n "$SUBJ_ID" ]; then
            oc_query "DELETE FROM subject WHERE subject_id = $SUBJ_ID" 2>/dev/null || true
        fi
    done
    echo "Existing CV subjects removed"
fi

# Record baseline
INITIAL_SITE_COUNT=$(oc_query "SELECT COUNT(*) FROM study WHERE parent_study_id = $CV_STUDY_ID AND status_id != 3")
INITIAL_SUBJECT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_subject ss JOIN study s ON ss.study_id = s.study_id WHERE (s.study_id = $CV_STUDY_ID OR s.parent_study_id = $CV_STUDY_ID) AND ss.status_id != 3")
echo "${INITIAL_SITE_COUNT:-0}" > /tmp/initial_site_count
echo "${INITIAL_SUBJECT_COUNT:-0}" > /tmp/initial_cv_subject_count
echo "Initial site count: ${INITIAL_SITE_COUNT:-0}"
echo "Initial CV subject count: ${INITIAL_SUBJECT_COUNT:-0}"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "CV-REG-2023"
focus_firefox
sleep 1

AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== add_study_site setup complete ==="
