#!/bin/bash
echo "=== Setting up clinical_data_audit task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/audit_findings.txt

# 1. Inject the backend database schema to create the target scenario
# We manually seed the EAV structure for the CRF, item_data, and audit_event.
echo "Seeding the audit scenario in PostgreSQL..."

docker exec -i oc-postgres psql -U clinica openclinica << 'EOF'
DO $$
DECLARE
    v_root_id INT;
    v_mrivera_id INT;
    v_study_id INT;
    v_study_subject_id INT;
    v_sed_id INT;
    v_crf_id INT;
    v_crf_version_id INT;
    v_item_group_id INT;
    v_item_id INT;
    v_event_id INT;
    v_event_crf_id INT;
    v_item_data_id INT;
BEGIN
    -- Resolve IDs
    SELECT user_id INTO v_root_id FROM user_account WHERE user_name = 'root' LIMIT 1;
    SELECT study_id INTO v_study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1;
    SELECT study_subject_id INTO v_study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = v_study_id LIMIT 1;

    -- Ensure 'mrivera' exists to match the audit trail
    IF NOT EXISTS (SELECT 1 FROM user_account WHERE user_name = 'mrivera') THEN
        INSERT INTO user_account (user_name, first_name, last_name, passwd, status_id, owner_id, date_created) 
        VALUES ('mrivera', 'Maria', 'Rivera', 'hash', 1, v_root_id, NOW());
    END IF;
    SELECT user_id INTO v_mrivera_id FROM user_account WHERE user_name = 'mrivera' LIMIT 1;

    -- Clean up any conflicting pre-existing events for DM-101
    DELETE FROM study_event WHERE study_subject_id = v_study_subject_id;
    DELETE FROM study_event_definition WHERE study_id = v_study_id AND name = 'Baseline Assessment';

    -- Build Study Event Definition
    INSERT INTO study_event_definition (study_id, name, type, owner_id, status_id, repeating, oc_oid, ordinal) 
    VALUES (v_study_id, 'Baseline Assessment', 'Scheduled', v_root_id, 1, false, 'SE_BASE_01', 1) 
    RETURNING study_event_definition_id INTO v_sed_id;

    -- Build CRF & Version
    INSERT INTO crf (name, status_id, owner_id, oc_oid) 
    VALUES ('Vital Signs', 1, v_root_id, 'F_VITAL_01') 
    RETURNING crf_id INTO v_crf_id;

    INSERT INTO crf_version (crf_id, name, status_id, owner_id, oc_oid) 
    VALUES (v_crf_id, 'v1.0', 1, v_root_id, 'V_VITAL_01') 
    RETURNING crf_version_id INTO v_crf_version_id;

    INSERT INTO event_definition_crf (study_event_definition_id, study_id, crf_id, default_version_id, status_id, owner_id) 
    VALUES (v_sed_id, v_study_id, v_crf_id, v_crf_version_id, 1, v_root_id);

    -- Build Item & Metadata
    INSERT INTO item_group (name, crf_id, status_id, owner_id, oc_oid) 
    VALUES ('Vitals Group', v_crf_id, 1, v_root_id, 'IG_VITAL_01') 
    RETURNING item_group_id INTO v_item_group_id;

    INSERT INTO item (name, description, item_data_type_id, status_id, owner_id, oc_oid) 
    VALUES ('SYSBP', 'Systolic BP', 2, 1, v_root_id, 'I_SYSBP_01') 
    RETURNING item_id INTO v_item_id;

    INSERT INTO item_group_metadata (item_group_id, crf_version_id, status_id, owner_id, header, show_group) 
    VALUES (v_item_group_id, v_crf_version_id, 1, v_root_id, 'Vitals', true);

    INSERT INTO item_form_metadata (item_id, crf_version_id, header, show_item, status_id, owner_id) 
    VALUES (v_item_id, v_crf_version_id, 'Systolic BP', true, 1, v_root_id);

    -- Build Data Event (Status 4 = Completed)
    INSERT INTO study_event (study_event_definition_id, study_subject_id, status_id, owner_id, date_created) 
    VALUES (v_sed_id, v_study_subject_id, 4, v_root_id, NOW()) 
    RETURNING study_event_id INTO v_event_id;

    INSERT INTO event_crf (study_event_id, crf_version_id, study_subject_id, status_id, owner_id, date_created) 
    VALUES (v_event_id, v_crf_version_id, v_study_subject_id, 2, v_root_id, NOW()) 
    RETURNING event_crf_id INTO v_event_crf_id;

    -- Inject current data (125)
    INSERT INTO item_data (item_id, event_crf_id, value, status_id, owner_id, date_created) 
    VALUES (v_item_id, v_event_crf_id, '125', 2, v_root_id, NOW()) 
    RETURNING item_data_id INTO v_item_data_id;

    -- Inject the AUDIT TARGET (Original: 195 -> Modified: 125, by: mrivera, reason: transcription error)
    INSERT INTO audit_event (audit_date, audit_table, user_id, entity_id, reason_for_change, action_message)
    VALUES (NOW() - INTERVAL '1 day', 'item_data', v_mrivera_id, v_item_data_id, 'transcription error', 'Item data value updated from 195 to 125.');

END $$;
EOF

echo "Scenario successfully seeded."

# 2. Configure the Browser and Session
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"

# Maximize Firefox for agent visibility
focus_firefox
sleep 1
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="