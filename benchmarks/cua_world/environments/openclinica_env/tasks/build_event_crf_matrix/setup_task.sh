#!/bin/bash
echo "=== Setting up build_event_crf_matrix task ==="

source /workspace/scripts/task_utils.sh

# 1. Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Ensure CRFs exist
for CRF_NAME in "Demographics" "Vital Signs" "Lab Results"; do
    SAFE_NAME=$(echo "$CRF_NAME" | sed 's/ /_/g')
    
    # Create CRF if missing
    oc_query "INSERT INTO crf (name, status_id, owner_id, date_created, oc_oid) 
              SELECT '$CRF_NAME', 1, 1, NOW(), 'C_${SAFE_NAME}_V1' 
              WHERE NOT EXISTS (SELECT 1 FROM crf WHERE name = '$CRF_NAME');"
              
    CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name = '$CRF_NAME' LIMIT 1")
    
    # Create CRF Version if missing
    oc_query "INSERT INTO crf_version (crf_id, name, description, revision_notes, status_id, owner_id, date_created, oc_oid) 
              SELECT $CRF_ID, 'v1.0', 'Initial', 'Init', 1, 1, NOW(), 'F_${SAFE_NAME}_V1' 
              WHERE NOT EXISTS (SELECT 1 FROM crf_version WHERE crf_id = $CRF_ID);"
    
    echo "Ensured CRF exists: $CRF_NAME (ID: $CRF_ID)"
done

# 3. Ensure Event Definitions exist
for EVENT_NAME in "Screening Visit" "Baseline Visit" "Week 12 Final Visit"; do
    SAFE_NAME=$(echo "$EVENT_NAME" | sed 's/ /_/g')
    
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid) 
              SELECT $DM_STUDY_ID, '$EVENT_NAME', '$EVENT_NAME', false, 'Scheduled', 1, 1, NOW(), 'SE_${SAFE_NAME}' 
              WHERE NOT EXISTS (SELECT 1 FROM study_event_definition WHERE name = '$EVENT_NAME' AND study_id = $DM_STUDY_ID);"
              
    echo "Ensured Event Definition exists: $EVENT_NAME"
done

# 4. Clean up any existing assignments for this study (clean slate for task)
echo "Removing any pre-existing CRF assignments for DM Trial..."
oc_query "DELETE FROM event_definition_crf WHERE study_id = $DM_STUDY_ID" 2>/dev/null || true

# 5. Record baseline states for verification
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

INITIAL_EDC_COUNT=$(oc_query "SELECT COUNT(*) FROM event_definition_crf WHERE study_id = $DM_STUDY_ID")
echo "${INITIAL_EDC_COUNT:-0}" > /tmp/initial_edc_count

NONCE=$(generate_result_nonce)
echo "Integrity Nonce: $NONCE"
date +%s > /tmp/task_start_time.txt

# 6. Ensure Firefox is running, logged in, and focused on right study
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

echo "=== Task setup complete ==="