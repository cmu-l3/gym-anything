#!/bin/bash
echo "=== Setting up build_custom_dataset task ==="

source /workspace/scripts/task_utils.sh

# 1. Resolve Study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial (DM-TRIAL-2024) not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Clean up any existing dataset with the target name to ensure a clean slate
echo "Checking for existing 'Safety_PK_Analysis' dataset..."
EXISTING_DS_ID=$(oc_query "SELECT dataset_id FROM dataset WHERE name = 'Safety_PK_Analysis' LIMIT 1")

if [ -n "$EXISTING_DS_ID" ]; then
    echo "Removing pre-existing dataset (id=$EXISTING_DS_ID)..."
    oc_query "DELETE FROM dataset_item_status WHERE dataset_id = $EXISTING_DS_ID" 2>/dev/null || true
    oc_query "DELETE FROM dataset_study_group_class_map WHERE dataset_id = $EXISTING_DS_ID" 2>/dev/null || true
    oc_query "DELETE FROM dataset_crf_version_map WHERE dataset_id = $EXISTING_DS_ID" 2>/dev/null || true
    oc_query "DELETE FROM dataset_filter_map WHERE dataset_id = $EXISTING_DS_ID" 2>/dev/null || true
    oc_query "DELETE FROM archived_dataset_file WHERE dataset_id = $EXISTING_DS_ID" 2>/dev/null || true
    oc_query "DELETE FROM dataset WHERE dataset_id = $EXISTING_DS_ID" 2>/dev/null || true
    echo "Cleanup complete."
fi

# 3. Clean up the Downloads and Desktop folders so we can cleanly detect the exported file
echo "Cleaning up Downloads directory..."
mkdir -p /home/ga/Downloads
mkdir -p /home/ga/Desktop
find /home/ga/Downloads /home/ga/Desktop -maxdepth 1 -type f \( -name "*.zip" -o -name "*.txt" -o -name "*.tsv" -o -name "*.xls" -o -name "*.csv" \) -delete 2>/dev/null || true

# 4. Record Baseline State
date +%s > /tmp/task_start_timestamp
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# 5. Ensure OpenClinica is running and user is logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# Take proof of starting state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="