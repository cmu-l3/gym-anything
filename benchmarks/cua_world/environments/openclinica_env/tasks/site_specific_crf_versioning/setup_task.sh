#!/bin/bash
echo "=== Setting up site_specific_crf_versioning task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time

# Wait for OpenClinica to be fully up
wait_for_window "firefox\|mozilla\|OpenClinica" 30 || true
ensure_logged_in

# 1. Resolve Parent Study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial (DM-TRIAL-2024) not found."
    exit 1
fi
echo "Parent Study ID: $DM_STUDY_ID"

# 2. Ensure "Boston Medical Center" Site Exists
oc_query "INSERT INTO study (name, unique_identifier, status_id, parent_study_id, owner_id, date_created, protocol_type, principal_investigator) 
          SELECT 'Boston Medical Center', 'DM-BMC-001', 1, $DM_STUDY_ID, 1, NOW(), 'interventional', 'Dr. Smith' 
          WHERE NOT EXISTS (SELECT 1 FROM study WHERE unique_identifier = 'DM-BMC-001');"
SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-BMC-001' LIMIT 1")
echo "Site ID: $SITE_ID"

# 3. Ensure "Baseline Assessment" Event Definition Exists
oc_query "INSERT INTO study_event_definition (study_id, name, type, repeating, status_id, owner_id, date_created, oc_oid, ordinal) 
          SELECT $DM_STUDY_ID, 'Baseline Assessment', 'Scheduled', false, 1, 1, NOW(), 'SE_BASELINE', 1 
          WHERE NOT EXISTS (SELECT 1 FROM study_event_definition WHERE study_id=$DM_STUDY_ID AND name='Baseline Assessment');"
SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id=$DM_STUDY_ID AND name='Baseline Assessment' LIMIT 1")
echo "SED ID: $SED_ID"

# 4. Ensure "Physical Exam" CRF Exists
oc_query "INSERT INTO crf (name, description, status_id, owner_id, date_created, oc_oid, source_study_id) 
          SELECT 'Physical Exam', 'Physical Exam Form', 1, 1, NOW(), 'F_PHYSICAL_EXAM', $DM_STUDY_ID 
          WHERE NOT EXISTS (SELECT 1 FROM crf WHERE name='Physical Exam');"
CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name='Physical Exam' LIMIT 1")
echo "CRF ID: $CRF_ID"

# 5. Ensure CRF Versions v1.0 and v2.0 Exist
oc_query "INSERT INTO crf_version (crf_id, name, description, status_id, owner_id, date_created, oc_oid, revision_notes) 
          SELECT $CRF_ID, 'v1.0', 'Version 1', 1, 1, NOW(), 'F_PHYSICAL_EXAM_V10', 'Initial' 
          WHERE NOT EXISTS (SELECT 1 FROM crf_version WHERE crf_id=$CRF_ID AND name='v1.0');"
oc_query "INSERT INTO crf_version (crf_id, name, description, status_id, owner_id, date_created, oc_oid, revision_notes) 
          SELECT $CRF_ID, 'v2.0', 'Version 2', 1, 1, NOW(), 'F_PHYSICAL_EXAM_V20', 'Updated' 
          WHERE NOT EXISTS (SELECT 1 FROM crf_version WHERE crf_id=$CRF_ID AND name='v2.0');"

V1_ID=$(oc_query "SELECT crf_version_id FROM crf_version WHERE crf_id=$CRF_ID AND name='v1.0' LIMIT 1")
V2_ID=$(oc_query "SELECT crf_version_id FROM crf_version WHERE crf_id=$CRF_ID AND name='v2.0' LIMIT 1")
echo "V1 ID: $V1_ID, V2 ID: $V2_ID"

# 6. Map CRF to Parent Study Event Definition using v1.0
oc_query "DELETE FROM event_definition_crf WHERE study_event_definition_id=$SED_ID AND study_id=$DM_STUDY_ID AND crf_id=$CRF_ID;"
oc_query "INSERT INTO event_definition_crf (study_event_definition_id, study_id, crf_id, required_crf, double_entry, password_required, status_id, owner_id, date_created, default_version_id) 
          VALUES ($SED_ID, $DM_STUDY_ID, $CRF_ID, true, false, false, 1, 1, NOW(), $V1_ID);"

# 7. Clean Site-Level Override (if any exists from previous runs)
oc_query "DELETE FROM event_definition_crf WHERE study_event_definition_id=$SED_ID AND study_id=$SITE_ID AND crf_id=$CRF_ID;"

# Set browser context to parent study so agent has to deliberately switch
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 2

# Save initial IDs for export script
echo "{\"dm_id\": \"$DM_STUDY_ID\", \"site_id\": \"$SITE_ID\", \"sed_id\": \"$SED_ID\", \"crf_id\": \"$CRF_ID\", \"v1_id\": \"$V1_ID\", \"v2_id\": \"$V2_ID\"}" > /tmp/task_ids.json
chmod 666 /tmp/task_ids.json

# Audit log baseline
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

# Anti-gaming Nonce
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="