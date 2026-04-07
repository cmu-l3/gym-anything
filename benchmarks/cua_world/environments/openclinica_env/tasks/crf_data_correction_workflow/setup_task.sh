#!/bin/bash
echo "=== Setting up crf_data_correction_workflow task ==="

source /workspace/scripts/task_utils.sh

# Get study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# -----------------------------------------------------------------------------
# SQL Injection to construct a mock "Vital Signs" CRF and populate with errors
# -----------------------------------------------------------------------------
cat > /tmp/inject_crf.sql << 'EOF'
DO $$
DECLARE
    v_study_id INT;
    v_crf_id INT;
    v_crf_version_id INT;
    v_item_group_id INT;
    v_sysbp_item_id INT;
    v_hr_item_id INT;
    v_response_set_id INT;
    v_sed_id INT;
    v_dm101_ss_id INT;
    v_dm102_ss_id INT;
    v_dm101_se_id INT;
    v_dm102_se_id INT;
    v_dm101_ec_id INT;
    v_dm102_ec_id INT;
BEGIN
    SELECT study_id INTO v_study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1;

    -- Clean up existing mock Vital Signs data
    DELETE FROM item_data WHERE event_crf_id IN (SELECT event_crf_id FROM event_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id IN (SELECT crf_id FROM crf WHERE name = 'Vital Signs')));
    DELETE FROM event_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id IN (SELECT crf_id FROM crf WHERE name = 'Vital Signs'));
    DELETE FROM event_definition_crf WHERE crf_id IN (SELECT crf_id FROM crf WHERE name = 'Vital Signs');
    DELETE FROM item_form_metadata WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id IN (SELECT crf_id FROM crf WHERE name = 'Vital Signs'));
    DELETE FROM item_group_metadata WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id IN (SELECT crf_id FROM crf WHERE name = 'Vital Signs'));
    DELETE FROM response_set WHERE version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id IN (SELECT crf_id FROM crf WHERE name = 'Vital Signs'));
    DELETE FROM crf_version WHERE crf_id IN (SELECT crf_id FROM crf WHERE name = 'Vital Signs');
    DELETE FROM item_group WHERE crf_id IN (SELECT crf_id FROM crf WHERE name = 'Vital Signs');
    DELETE FROM crf WHERE name = 'Vital Signs';

    -- Build CRF Hierarchy
    INSERT INTO crf (status_id, name, description, owner_id, date_created, oc_oid, source_study_id)
    VALUES (1, 'Vital Signs', 'Vital Signs CRF', 1, NOW(), 'F_VITALSIGNS_' || floor(random() * 10000)::text, v_study_id) RETURNING crf_id INTO v_crf_id;

    INSERT INTO crf_version (crf_id, name, description, status_id, owner_id, date_created, oc_oid)
    VALUES (v_crf_id, 'v1.0', 'Initial version', 1, 1, NOW(), 'V_VITALSIGNS_' || floor(random() * 10000)::text) RETURNING crf_version_id INTO v_crf_version_id;

    INSERT INTO response_set (response_type_id, label, options_text, options_values, version_id)
    VALUES (1, 'Text', 'text', 'text', v_crf_version_id) RETURNING response_set_id INTO v_response_set_id;

    INSERT INTO item_group (name, crf_id, status_id, owner_id, date_created, oc_oid)
    VALUES ('Vital Signs Group', v_crf_id, 1, 1, NOW(), 'IG_VITALSIGNS_' || floor(random() * 10000)::text) RETURNING item_group_id INTO v_item_group_id;

    INSERT INTO item_group_metadata (item_group_id, header, crf_version_id, borders, show_group, repeating)
    VALUES (v_item_group_id, 'Vital Signs', v_crf_version_id, 0, true, false);

    INSERT INTO item (name, description, units, phi_status, item_data_type_id, status_id, owner_id, date_created, oc_oid)
    VALUES ('SYSBP', 'Systolic Blood Pressure', 'mmHg', false, 6, 1, 1, NOW(), 'I_VITAL_SYSBP_' || floor(random() * 10000)::text) RETURNING item_id INTO v_sysbp_item_id;

    INSERT INTO item (name, description, units, phi_status, item_data_type_id, status_id, owner_id, date_created, oc_oid)
    VALUES ('HR', 'Heart Rate', 'bpm', false, 6, 1, 1, NOW(), 'I_VITAL_HR_' || floor(random() * 10000)::text) RETURNING item_id INTO v_hr_item_id;

    INSERT INTO item_form_metadata (item_id, crf_version_id, header, show_item, response_set_id, item_group_id, ordinal, required)
    VALUES (v_sysbp_item_id, v_crf_version_id, 'Systolic BP', true, v_response_set_id, v_item_group_id, 1, true);

    INSERT INTO item_form_metadata (item_id, crf_version_id, header, show_item, response_set_id, item_group_id, ordinal, required)
    VALUES (v_hr_item_id, v_crf_version_id, 'Heart Rate', true, v_response_set_id, v_item_group_id, 2, true);

    -- Link to Study Event Definition
    SELECT study_event_definition_id INTO v_sed_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = v_study_id LIMIT 1;
    IF v_sed_id IS NULL THEN
        INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal)
        VALUES (v_study_id, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASE_' || floor(random() * 10000)::text, 1) RETURNING study_event_definition_id INTO v_sed_id;
    END IF;

    INSERT INTO event_definition_crf (study_event_definition_id, study_id, crf_id, required_crf, double_entry, require_all_text_filled, decision_conditions, null_values, status_id, owner_id, date_created, default_version_id)
    VALUES (v_sed_id, v_study_id, v_crf_id, true, false, false, false, false, 1, 1, NOW(), v_crf_version_id);

    -- Add Subjects Events & Data
    SELECT study_subject_id INTO v_dm101_ss_id FROM study_subject WHERE label = 'DM-101' AND study_id = v_study_id LIMIT 1;
    SELECT study_subject_id INTO v_dm102_ss_id FROM study_subject WHERE label = 'DM-102' AND study_id = v_study_id LIMIT 1;

    DELETE FROM study_event WHERE study_subject_id IN (v_dm101_ss_id, v_dm102_ss_id) AND study_event_definition_id = v_sed_id;

    INSERT INTO study_event (study_subject_id, study_event_definition_id, start_date, status_id, owner_id, date_created, sample_ordinal)
    VALUES (v_dm101_ss_id, v_sed_id, '2024-01-15', 1, 1, NOW(), 1) RETURNING study_event_id INTO v_dm101_se_id;

    INSERT INTO study_event (study_subject_id, study_event_definition_id, start_date, status_id, owner_id, date_created, sample_ordinal)
    VALUES (v_dm102_ss_id, v_sed_id, '2024-01-16', 1, 1, NOW(), 1) RETURNING study_event_id INTO v_dm102_se_id;

    -- Create completed event CRFs
    INSERT INTO event_crf (study_event_id, crf_version_id, status_id, owner_id, date_created, completion_status_id, date_completed)
    VALUES (v_dm101_se_id, v_crf_version_id, 2, 1, NOW(), 1, NOW()) RETURNING event_crf_id INTO v_dm101_ec_id;

    INSERT INTO event_crf (study_event_id, crf_version_id, status_id, owner_id, date_created, completion_status_id, date_completed)
    VALUES (v_dm102_se_id, v_crf_version_id, 2, 1, NOW(), 1, NOW()) RETURNING event_crf_id INTO v_dm102_ec_id;

    -- Insert erroneous Item Data
    INSERT INTO item_data (item_id, event_crf_id, status_id, owner_id, date_created, value)
    VALUES (v_sysbp_item_id, v_dm101_ec_id, 2, 1, NOW(), '190');

    INSERT INTO item_data (item_id, event_crf_id, status_id, owner_id, date_created, value)
    VALUES (v_hr_item_id, v_dm101_ec_id, 2, 1, NOW(), '70');

    INSERT INTO item_data (item_id, event_crf_id, status_id, owner_id, date_created, value)
    VALUES (v_sysbp_item_id, v_dm102_ec_id, 2, 1, NOW(), '120');

    INSERT INTO item_data (item_id, event_crf_id, status_id, owner_id, date_created, value)
    VALUES (v_hr_item_id, v_dm102_ec_id, 2, 1, NOW(), '45');
END $$;
EOF

echo "Executing SQL to construct Vital Signs CRF..."
docker exec oc-postgres psql -U clinica openclinica -f /tmp/inject_crf.sql 2>/dev/null || echo "WARNING: SQL execution returned an error."

# -----------------------------------------------------------------------------
# Create Corrections Document
# -----------------------------------------------------------------------------
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/monitor_corrections.txt << 'EOF'
CLINICAL MONITORING REPORT - CORRECTIONS REQUIRED
Study: Phase II Diabetes Trial (DM-TRIAL-2024)

During source data verification, the following transcription errors were found in the EDC system. Please correct these immediately in the "Vital Signs" CRF for the Baseline Assessment event.

1. Subject DM-101
   - Field: Systolic BP
   - Current EDC Value: 190
   - Correct Source Value: 119
   - Reason to log: Transcription error from source document

2. Subject DM-102
   - Field: Heart Rate
   - Current EDC Value: 45
   - Correct Source Value: 75
   - Reason to log: Typo during initial data entry
EOF
chown ga:ga /home/ga/Documents/monitor_corrections.txt

# -----------------------------------------------------------------------------
# Baselines & UI Setup
# -----------------------------------------------------------------------------
date +%s > /tmp/task_start_time
AUDIT_BASELINE=$(oc_query "SELECT COUNT(*) FROM audit_event WHERE reason_for_change IS NOT NULL")
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_rfc_baseline

if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== crf_data_correction_workflow setup complete ==="