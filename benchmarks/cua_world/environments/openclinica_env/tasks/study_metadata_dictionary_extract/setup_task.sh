#!/bin/bash
echo "=== Setting up study_metadata_dictionary_extract task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Clean up any pre-existing agent files from previous runs
rm -f /home/ga/study_metadata.xml 2>/dev/null
rm -f /home/ga/ae_codelists.json 2>/dev/null
rm -f /tmp/metadata_extract_result.json 2>/dev/null

# Inject the custom Adverse Events CRF structure directly into the database
# This ensures the CDISC ODM XML will contain the target CodeLists when downloaded.
echo "Injecting target metadata structures into the database..."

cat << 'EOF' > /tmp/inject_crf.sql
DO $$
DECLARE
    v_study_id integer;
    v_crf_id integer;
    v_crf_version_id integer;
    v_item_group_id integer;
    v_item_sev_id integer;
    v_item_rel_id integer;
    v_rs_sev_id integer;
    v_rs_rel_id integer;
    v_sed_id integer;
BEGIN
    -- Only insert if it doesn't already exist to allow idempotent setup
    IF EXISTS (SELECT 1 FROM crf WHERE name = 'Adverse Events') THEN
        RETURN;
    END IF;

    SELECT study_id INTO v_study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1;
    IF v_study_id IS NULL THEN
        RETURN;
    END IF;

    -- Create CRF
    INSERT INTO crf (status_id, name, description, owner_id, date_created, oc_oid, source_study_id)
    VALUES (1, 'Adverse Events', 'Adverse Events CRF', 1, NOW(), 'F_AE_1', v_study_id) 
    RETURNING crf_id INTO v_crf_id;

    -- Create CRF Version
    INSERT INTO crf_version (crf_id, status_id, name, description, revision_notes, owner_id, date_created, oc_oid)
    VALUES (v_crf_id, 1, 'v1.0', 'Initial', 'None', 1, NOW(), 'V_AE_V1_0') 
    RETURNING crf_version_id INTO v_crf_version_id;

    -- Create Item Group
    INSERT INTO item_group (status_id, name, crf_id, owner_id, date_created, oc_oid)
    VALUES (1, 'AE_SEC', v_crf_id, 1, NOW(), 'IG_AE_SEC') 
    RETURNING item_group_id INTO v_item_group_id;

    INSERT INTO item_group_metadata (item_group_id, crf_version_id, status_id, owner_id, date_created, repeating, show_group, borders)
    VALUES (v_item_group_id, v_crf_version_id, 1, 1, NOW(), false, true, 1);

    -- Create target Response Sets (These become the CDISC ODM CodeLists)
    INSERT INTO response_set (response_type_id, label, options_text, options_values, version_id)
    VALUES (5, 'SEV_RSP', 'Grade 1 (Mild - No intervention),Grade 2 (Moderate - Local intervention),Grade 3 (Severe - Hospitalization),Grade 4 (Life-threatening),Grade 5 (Fatal)', '1,2,3,4,5', v_crf_version_id) 
    RETURNING response_set_id INTO v_rs_sev_id;

    INSERT INTO response_set (response_type_id, label, options_text, options_values, version_id)
    VALUES (5, 'REL_RSP', 'Not Related (Unlikely),Possibly Related,Probably Related,Definitely Related', '1,2,3,4', v_crf_version_id) 
    RETURNING response_set_id INTO v_rs_rel_id;

    -- Create Items
    INSERT INTO item (status_id, name, description, units, owner_id, date_created, oc_oid, item_data_type_id)
    VALUES (1, 'AE_SEV', 'Severity', '', 1, NOW(), 'I_AE_SEV', 6) 
    RETURNING item_id INTO v_item_sev_id;

    INSERT INTO item (status_id, name, description, units, owner_id, date_created, oc_oid, item_data_type_id)
    VALUES (1, 'AE_REL', 'Relationship', '', 1, NOW(), 'I_AE_REL', 6) 
    RETURNING item_id INTO v_item_rel_id;

    -- Create Item Form Metadata mappings
    INSERT INTO item_form_metadata (item_id, crf_version_id, header, subheader, right_item_text, left_item_text, response_set_id, status_id, owner_id, date_created, show_item, required)
    VALUES (v_item_sev_id, v_crf_version_id, '', '', '', 'Severity of AE', v_rs_sev_id, 1, 1, NOW(), true, true);

    INSERT INTO item_form_metadata (item_id, crf_version_id, header, subheader, right_item_text, left_item_text, response_set_id, status_id, owner_id, date_created, show_item, required)
    VALUES (v_item_rel_id, v_crf_version_id, '', '', '', 'Relationship to study drug', v_rs_rel_id, 1, 1, NOW(), true, true);

    -- Link CRF to a Study Event to ensure it is included in ODM Export
    SELECT study_event_definition_id INTO v_sed_id FROM study_event_definition WHERE study_id = v_study_id LIMIT 1;
    IF v_sed_id IS NULL THEN
        INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal)
        VALUES (v_study_id, 'Adverse Events Log', 'AE Log', true, 'Unscheduled', 1, 1, NOW(), 'SE_AE_LOG', 1) 
        RETURNING study_event_definition_id INTO v_sed_id;
    END IF;

    INSERT INTO event_definition_crf (study_event_definition_id, study_id, crf_id, required_crf, double_entry, require_all_text_filled, decision_conditions, null_values, status_id, owner_id, date_created, default_version_id)
    VALUES (v_sed_id, v_study_id, v_crf_id, false, false, false, false, '', 1, 1, NOW(), v_crf_version_id);

END $$;
EOF

# Execute the injection script
docker exec -i oc-postgres psql -U clinica openclinica < /tmp/inject_crf.sql

# Ensure Firefox is running and logged in to OpenClinica
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in

# Ensure active study is DM-TRIAL-2024
switch_active_study "DM-TRIAL-2024"

# Set up browser window
focus_firefox
sleep 1

# Take initial screenshot showing starting state
take_screenshot /tmp/task_start_screenshot.png ga

echo "=== Task setup complete ==="