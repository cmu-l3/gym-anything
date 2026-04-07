#!/bin/bash
echo "=== Setting up optimize_crf_compliance_params task ==="

source /workspace/scripts/task_utils.sh

# 1. Resolve DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial (DM-TRIAL-2024) not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Ensure "Safety Follow-up" Event Definition exists
SED_EXISTS=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Safety Follow-up' AND status_id != 3 LIMIT 1")
if [ -z "$SED_EXISTS" ]; then
    echo "Creating 'Safety Follow-up' event definition..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Safety Follow-up', 'Safety follow-up visit', false, 'Scheduled', 1, 1, NOW(), 'SE_SAFETY_FOLLOW', 3)"
    SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Safety Follow-up' AND status_id != 3 LIMIT 1")
else
    echo "'Safety Follow-up' event definition already exists"
    SED_ID="$SED_EXISTS"
fi

# 3. Ensure target CRFs exist
for crf_name in "Adverse Events" "Lab Results" "Quality of Life"; do
    CRF_EXISTS=$(oc_query "SELECT crf_id FROM crf WHERE name = '$crf_name' AND status_id != 3 LIMIT 1")
    if [ -z "$CRF_EXISTS" ]; then
        echo "Creating CRF: $crf_name..."
        OID_PREFIX=$(echo "$crf_name" | sed -e 's/ //g' | tr '[:lower:]' '[:upper:]')
        oc_query "INSERT INTO crf (name, description, status_id, owner_id, date_created, oc_oid, source_study_id) VALUES ('$crf_name', 'Auto-generated for task', 1, 1, NOW(), 'F_' || '$OID_PREFIX', $DM_STUDY_ID)"
        CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name = '$crf_name' AND status_id != 3 LIMIT 1")
        oc_query "INSERT INTO crf_version (crf_id, name, description, status_id, owner_id, date_created, oc_oid) VALUES ($CRF_ID, 'v1.0', 'Initial', 1, 1, NOW(), 'F_' || '$OID_PREFIX' || '_V10')"
    fi
done

# 4. Assign CRFs to Event Definition with default parameters (Required=true, DDE=false, Pwd=false)
for crf_name in "Adverse Events" "Lab Results" "Quality of Life"; do
    CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name = '$crf_name' AND status_id != 3 LIMIT 1")
    CV_ID=$(oc_query "SELECT crf_version_id FROM crf_version WHERE crf_id = $CRF_ID LIMIT 1")
    
    EDC_EXISTS=$(oc_query "SELECT event_definition_crf_id FROM event_definition_crf WHERE study_event_definition_id = $SED_ID AND crf_id = $CRF_ID AND status_id != 3 LIMIT 1")
    
    if [ -n "$EDC_EXISTS" ]; then
        echo "Resetting assignments for $crf_name..."
        # Schema fallback (electronic_signature vs require_pwd)
        oc_query "UPDATE event_definition_crf SET required_crf = true, double_entry = false, electronic_signature = false, status_id = 1 WHERE event_definition_crf_id = $EDC_EXISTS" 2>/dev/null || \
        oc_query "UPDATE event_definition_crf SET required_crf = true, double_entry = false, require_pwd = false, status_id = 1 WHERE event_definition_crf_id = $EDC_EXISTS"
    else
        echo "Assigning $crf_name to Safety Follow-up..."
        oc_query "INSERT INTO event_definition_crf (study_event_definition_id, study_id, crf_id, required_crf, double_entry, electronic_signature, status_id, owner_id, date_created, default_version_id) VALUES ($SED_ID, $DM_STUDY_ID, $CRF_ID, true, false, false, 1, 1, NOW(), $CV_ID)" 2>/dev/null || \
        oc_query "INSERT INTO event_definition_crf (study_event_definition_id, study_id, crf_id, required_crf, double_entry, require_pwd, status_id, owner_id, date_created, default_version_id) VALUES ($SED_ID, $DM_STUDY_ID, $CRF_ID, true, false, false, 1, 1, NOW(), $CV_ID)"
    fi
done

# 5. Set up browser and session state
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# 6. Establish baseline metrics & anti-gaming protections
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

NONCE=$(generate_result_nonce)
echo "$NONCE" > /tmp/result_nonce

take_screenshot /tmp/task_start_screenshot.png
date +%s > /tmp/task_start_timestamp

echo "=== Setup complete ==="