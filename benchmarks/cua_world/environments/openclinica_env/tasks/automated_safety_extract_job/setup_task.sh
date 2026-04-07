#!/bin/bash
echo "=== Setting up automated_safety_extract_job task ==="

source /workspace/scripts/task_utils.sh

# Verify DB connection
DB_OK=$(oc_query "SELECT 1" 2>/dev/null || echo "0")
if [ "$DB_OK" != "1" ]; then
    echo "ERROR: Database not accessible"
    exit 1
fi

# Get DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# Clean up any pre-existing dataset with the target name
echo "Cleaning up pre-existing datasets..."
DATASET_IDS=$(oc_query "SELECT dataset_id FROM dataset WHERE LOWER(name) = 'idmc_weekly_safety'" 2>/dev/null || echo "")
if [ -n "$DATASET_IDS" ]; then
    for DID in $DATASET_IDS; do
        oc_query "DELETE FROM dataset_item_status WHERE dataset_id = $DID" 2>/dev/null || true
        oc_query "DELETE FROM dataset_study_group_class_map WHERE dataset_id = $DID" 2>/dev/null || true
        oc_query "DELETE FROM dataset_crf_version_map WHERE dataset_id = $DID" 2>/dev/null || true
        oc_query "DELETE FROM dataset WHERE dataset_id = $DID" 2>/dev/null || true
    done
    echo "Pre-existing dataset removed."
fi

# Clean up any pre-existing jobs with the target name
echo "Cleaning up pre-existing scheduled jobs..."
JOB_NAMES=$(oc_query "SELECT job_name FROM qrtz_job_details WHERE LOWER(job_name) LIKE '%idmc_monday_extract%'" 2>/dev/null || echo "")
if [ -n "$JOB_NAMES" ]; then
    for JNAME in $JOB_NAMES; do
        TRIGGERS=$(oc_query "SELECT trigger_name FROM qrtz_triggers WHERE job_name = '$JNAME'" 2>/dev/null || echo "")
        for TNAME in $TRIGGERS; do
            oc_query "DELETE FROM qrtz_cron_triggers WHERE trigger_name = '$TNAME'" 2>/dev/null || true
            oc_query "DELETE FROM qrtz_triggers WHERE trigger_name = '$TNAME'" 2>/dev/null || true
        done
        oc_query "DELETE FROM qrtz_job_details WHERE job_name = '$JNAME'" 2>/dev/null || true
    done
    echo "Pre-existing scheduled jobs removed."
fi

# Record baseline counts for audit
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

# Generate nonce
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"
date +%s > /tmp/task_start_timestamp

# Ensure Firefox running, logged in, and set to correct study
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

echo "=== Setup complete ==="