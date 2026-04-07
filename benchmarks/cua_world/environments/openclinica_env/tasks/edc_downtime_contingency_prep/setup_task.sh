#!/bin/bash
echo "=== Setting up edc_downtime_contingency_prep task ==="

source /workspace/scripts/task_utils.sh

# 1. Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi

# 2. Clean up any existing Vital Signs CRF records to ensure task is playable
EXISTING_CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE LOWER(TRIM(name)) = 'vital signs' LIMIT 1")
if [ -n "$EXISTING_CRF_ID" ]; then
    echo "Removing existing Vital Signs CRF for clean state..."
    oc_query "DELETE FROM item_data WHERE event_crf_id IN (SELECT ec.event_crf_id FROM event_crf ec JOIN crf_version cv ON ec.crf_version_id = cv.crf_version_id WHERE cv.crf_id = $EXISTING_CRF_ID)" 2>/dev/null || true
    oc_query "DELETE FROM event_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID)" 2>/dev/null || true
    oc_query "DELETE FROM event_definition_crf WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    oc_query "DELETE FROM event_definition_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID)" 2>/dev/null || true
    oc_query "DELETE FROM item_form_metadata WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID)" 2>/dev/null || true
    oc_query "DELETE FROM crf_version WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    oc_query "DELETE FROM crf WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
fi

# 3. Copy the CRF template file
if [ -f "/workspace/data/sample_crf.xls" ]; then
    cp /workspace/data/sample_crf.xls /home/ga/vital_signs_crf.xls
    chown ga:ga /home/ga/vital_signs_crf.xls
    chmod 644 /home/ga/vital_signs_crf.xls
    echo "CRF template copied to /home/ga/vital_signs_crf.xls"
else
    echo "WARNING: CRF template not found at /workspace/data/sample_crf.xls"
fi

# 4. Clean target directory
rm -rf /home/ga/Documents/Downtime_Forms 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 5. Generate anti-gaming metadata
date +%s > /tmp/task_start_timestamp
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# 6. Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="