#!/bin/bash
echo "=== Setting up interim_data_extract task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce for integrity
date +%s > /tmp/task_start_time.txt
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# 1. Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Cleanup any pre-existing datasets with similar names to ensure clean state
echo "Cleaning up pre-existing datasets..."
EXISTING_DATASET_IDS=$(oc_query "SELECT dataset_id FROM dataset WHERE study_id = $DM_STUDY_ID AND LOWER(name) LIKE '%dm2024%'")
for DS_ID in $EXISTING_DATASET_IDS; do
    oc_query "DELETE FROM archived_dataset_file WHERE dataset_id = $DS_ID" 2>/dev/null || true
    oc_query "DELETE FROM dataset_study_group_class_map WHERE dataset_id = $DS_ID" 2>/dev/null || true
    oc_query "DELETE FROM dataset_filter_map WHERE dataset_id = $DS_ID" 2>/dev/null || true
    oc_query "DELETE FROM dataset_crf_version_map WHERE dataset_id = $DS_ID" 2>/dev/null || true
    oc_query "DELETE FROM dataset_item_status WHERE dataset_id = $DS_ID" 2>/dev/null || true
    oc_query "DELETE FROM dataset WHERE dataset_id = $DS_ID" 2>/dev/null || true
done

# 3. Ensure Baseline Assessment event definition exists
BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3 LIMIT 1")
if [ -z "$BASELINE_SED_ID" ]; then
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASE_EXTRACT', 1) RETURNING study_event_definition_id" > /tmp/sed_id.txt
    BASELINE_SED_ID=$(cat /tmp/sed_id.txt | grep -o '[0-9]*' | head -1)
fi

# 4. Create Vital Signs CRF structure (bare minimum for extraction engine)
CRF_EXISTS=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Vital Signs' LIMIT 1")
if [ -z "$CRF_EXISTS" ]; then
    echo "Seeding Vital Signs CRF and Clinical Data..."
    
    # Insert CRF
    oc_query "INSERT INTO crf (status_id, name, description, owner_id, date_created, oc_oid) VALUES (1, 'Vital Signs', 'Vital Signs CRF', 1, NOW(), 'F_VITALSI_1')"
    CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Vital Signs' LIMIT 1")
    
    # Insert CRF Version
    oc_query "INSERT INTO crf_version (crf_id, status_id, name, description, owner_id, date_created, oc_oid) VALUES ($CRF_ID, 1, 'v1.0', 'Initial version', 1, NOW(), 'F_VITALSI_1_V10')"
    CRF_VER_ID=$(oc_query "SELECT crf_version_id FROM crf_version WHERE crf_id = $CRF_ID LIMIT 1")
    
    # Assign to Event Definition
    oc_query "INSERT INTO event_definition_crf (study_event_definition_id, study_id, crf_id, required_crf, double_entry, require_all_text_valid, status_id, owner_id, date_created, default_version_id) VALUES ($BASELINE_SED_ID, $DM_STUDY_ID, $CRF_ID, true, false, false, 1, 1, NOW(), $CRF_VER_ID)"
    
    # Create Item Group
    oc_query "INSERT INTO item_group (name, crf_id, status_id, owner_id, date_created, oc_oid) VALUES ('IG_VITALS', $CRF_ID, 1, 1, NOW(), 'IG_VITALS_1')"
    IG_ID=$(oc_query "SELECT item_group_id FROM item_group WHERE name = 'IG_VITALS' LIMIT 1")
    
    # Create Items and Link to Group
    ITEMS=("SYSBP" "DIABP" "HR" "TEMP" "WEIGHT")
    for ITEM_NAME in "${ITEMS[@]}"; do
        oc_query "INSERT INTO item (name, description, item_data_type_id, status_id, owner_id, date_created, oc_oid) VALUES ('$ITEM_NAME', '$ITEM_NAME', 6, 1, 1, NOW(), 'I_VITAL_$ITEM_NAME')"
        ITEM_ID=$(oc_query "SELECT item_id FROM item WHERE name = '$ITEM_NAME' LIMIT 1")
        oc_query "INSERT INTO item_group_metadata (item_group_id, item_id, crf_version_id, status_id, owner_id, date_created) VALUES ($IG_ID, $ITEM_ID, $CRF_VER_ID, 1, 1, NOW())"
    done
    
    # Insert Subject Data for DM-101, DM-102, DM-103
    for SUBJ in "DM-101" "DM-102" "DM-103"; do
        # Ensure subject exists
        SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ' AND study_id = $DM_STUDY_ID LIMIT 1")
        if [ -z "$SS_ID" ]; then
            oc_query "INSERT INTO subject (status_id, owner_id, date_created, gender) VALUES (1, 1, NOW(), 'm')"
            SUBJ_ID=$(oc_query "SELECT subject_id FROM subject ORDER BY subject_id DESC LIMIT 1")
            oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, oc_oid) VALUES ('$SUBJ', $SUBJ_ID, $DM_STUDY_ID, 1, 1, NOW(), 'SS_$SUBJ')"
            SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ' AND study_id = $DM_STUDY_ID LIMIT 1")
        fi
        
        # Create Event
        oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, status_id, owner_id, date_created) VALUES ($SS_ID, $BASELINE_SED_ID, 4, 1, NOW())"
        EVENT_ID=$(oc_query "SELECT study_event_id FROM study_event WHERE study_subject_id = $SS_ID ORDER BY study_event_id DESC LIMIT 1")
        
        # Create Event CRF
        oc_query "INSERT INTO event_crf (study_event_id, crf_version_id, status_id, owner_id, date_created) VALUES ($EVENT_ID, $CRF_VER_ID, 4, 1, NOW())"
        ECRF_ID=$(oc_query "SELECT event_crf_id FROM event_crf WHERE study_event_id = $EVENT_ID LIMIT 1")
        
        # Insert Item Data (Random realistic values)
        SYS_VAL=$((120 + RANDOM % 30)); DIA_VAL=$((70 + RANDOM % 20)); HR_VAL=$((60 + RANDOM % 30)); TEMP_VAL="36.8"; WT_VAL="80.5"
        VALS=("$SYS_VAL" "$DIA_VAL" "$HR_VAL" "$TEMP_VAL" "$WT_VAL")
        
        for i in "${!ITEMS[@]}"; do
            ITEM_ID=$(oc_query "SELECT item_id FROM item WHERE name = '${ITEMS[$i]}' LIMIT 1")
            oc_query "INSERT INTO item_data (item_id, event_crf_id, value, status_id, owner_id, date_created) VALUES ($ITEM_ID, $ECRF_ID, '${VALS[$i]}', 1, 1, NOW())"
        done
    done
fi

# 5. Clear Downloads directory of previous task files
rm -f /home/ga/Downloads/* 2>/dev/null || true

# 6. Baseline metrics
DATASET_COUNT=$(oc_query "SELECT COUNT(*) FROM dataset WHERE study_id = $DM_STUDY_ID AND status_id != 5")
echo "${DATASET_COUNT:-0}" > /tmp/initial_dataset_count

AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

# 7. Start UI
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

echo "=== interim_data_extract setup complete ==="