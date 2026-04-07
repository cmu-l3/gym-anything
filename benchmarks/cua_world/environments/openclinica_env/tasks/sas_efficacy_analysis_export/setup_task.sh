#!/bin/bash
echo "=== Setting up sas_efficacy_analysis_export task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up desktop environment
echo "Cleaning up filesystem..."
rm -rf /home/ga/Documents/SAS_Analysis 2>/dev/null || true
rm -f /home/ga/Downloads/*.zip 2>/dev/null || true

# 2. Inject dummy CRFs directly via PL/pgSQL to ensure they appear in the Dataset Builder
echo "Ensuring required CRFs exist in the database..."
docker exec -i oc-postgres psql -U clinica openclinica << 'EOF'
DO $$
DECLARE
    v_study_id integer;
    v_sed_id integer;
    v_crf_id integer;
    v_cv_id integer;
    v_item_id integer;
    crf_name text;
BEGIN
    -- Get DM Trial study ID
    SELECT study_id INTO v_study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1;

    IF v_study_id IS NOT NULL THEN
        -- Ensure an event exists to bind the CRFs
        SELECT study_event_definition_id INTO v_sed_id FROM study_event_definition WHERE study_id = v_study_id AND name = 'Analysis Event' LIMIT 1;
        IF v_sed_id IS NULL THEN
            INSERT INTO study_event_definition (study_id, name, type, repeating, status_id, owner_id, date_created)
            VALUES (v_study_id, 'Analysis Event', 'Scheduled', false, 1, 1, NOW()) RETURNING study_event_definition_id INTO v_sed_id;
        END IF;

        -- Create each required CRF if it doesn't already exist
        FOREACH crf_name IN ARRAY ARRAY['Demographics', 'Vital Signs', 'Lab Results', 'Adverse Events']
        LOOP
            SELECT crf_id INTO v_crf_id FROM crf WHERE name = crf_name LIMIT 1;
            IF v_crf_id IS NULL THEN
                INSERT INTO crf (name, status_id, owner_id, date_created) VALUES (crf_name, 1, 1, NOW()) RETURNING crf_id INTO v_crf_id;
                INSERT INTO crf_version (crf_id, name, status_id, owner_id, date_created) VALUES (v_crf_id, 'v1.0', 1, 1, NOW()) RETURNING crf_version_id INTO v_cv_id;
                INSERT INTO event_definition_crf (study_event_definition_id, crf_id, default_version_id, status_id, owner_id, date_created)
                VALUES (v_sed_id, v_crf_id, v_cv_id, 1, 1, NOW());

                INSERT INTO item (name, description, item_data_type_id, status_id, owner_id, date_created)
                VALUES (crf_name || '_Item', 'Data for ' || crf_name, 1, 1, 1, NOW()) RETURNING item_id INTO v_item_id;

                INSERT INTO item_form_metadata (item_id, crf_version_id, header, show_item, status_id, owner_id)
                VALUES (v_item_id, v_cv_id, crf_name || ' Data', true, 1, 1);
            END IF;
        END LOOP;
    END IF;
END $$;
EOF

# 3. Clean up any pre-existing dataset with the target name
echo "Cleaning up pre-existing datasets..."
EXISTING_DS=$(oc_query "SELECT dataset_id FROM dataset WHERE name = 'SAS_Efficacy_Data'")
if [ -n "$EXISTING_DS" ]; then
    for DS_ID in $EXISTING_DS; do
        oc_query "DELETE FROM dataset_item_status WHERE dataset_id = $DS_ID" 2>/dev/null || true
        oc_query "DELETE FROM dataset WHERE dataset_id = $DS_ID" 2>/dev/null || true
    done
fi

# 4. Record baseline audit state
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
date +%s > /tmp/task_start_timestamp

# 5. Start browser and log in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="