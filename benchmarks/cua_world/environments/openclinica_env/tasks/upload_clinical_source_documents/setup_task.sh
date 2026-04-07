#!/bin/bash
echo "=== Setting up upload_clinical_source_documents task ==="

source /workspace/scripts/task_utils.sh

# 1. Generate realistic PDF source documents using ImageMagick
echo "Generating source document PDFs..."
mkdir -p /home/ga/source_docs
chown ga:ga /home/ga/source_docs

convert -size 800x600 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
  -draw "text 50,50 'DM-101 ECG Report'" \
  -draw "text 50,100 'Result: Normal Sinus Rhythm'" \
  -draw "text 50,150 'Date: 2024-01-15'" \
  /home/ga/source_docs/DM-101_ECG.pdf

convert -size 800x600 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
  -draw "text 50,50 'DM-102 Laboratory Report'" \
  -draw "text 50,100 'Result: HbA1c 7.2%'" \
  -draw "text 50,150 'Date: 2024-01-16'" \
  /home/ga/source_docs/DM-102_LabReport.pdf

chown ga:ga /home/ga/source_docs/*.pdf
chmod 644 /home/ga/source_docs/*.pdf
echo "Generated DM-101_ECG.pdf and DM-102_LabReport.pdf"

# 2. Inject the "Central Review Uploads" CRF via SQL
echo "Configuring database records for Central Review Uploads CRF..."
cat << 'EOF' > /tmp/setup_crf.sql
DO $$
DECLARE
    v_rt_single INT;
    v_rt_file INT;
    v_rt_text INT;
    v_dt_file INT;
    v_dt_string INT;
    v_study_id INT;
    v_sed_id INT;
    v_ss_101 INT;
    v_ss_102 INT;
BEGIN
    -- Safely resolve type IDs from OpenClinica schema
    SELECT COALESCE((SELECT response_type_id FROM response_type WHERE LOWER(name) = 'single-select' LIMIT 1), 5) INTO v_rt_single;
    SELECT COALESCE((SELECT response_type_id FROM response_type WHERE LOWER(name) = 'file' LIMIT 1), 6) INTO v_rt_file;
    SELECT COALESCE((SELECT response_type_id FROM response_type WHERE LOWER(name) = 'text' LIMIT 1), 1) INTO v_rt_text;
    SELECT COALESCE((SELECT item_data_type_id FROM item_data_type WHERE LOWER(code) = 'file' LIMIT 1), 9) INTO v_dt_file;
    SELECT COALESCE((SELECT item_data_type_id FROM item_data_type WHERE LOWER(code) = 'st' LIMIT 1), 1) INTO v_dt_string;

    -- Resolve Study and Event Definition
    SELECT study_id INTO v_study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1;
    
    -- Ensure Baseline Assessment exists
    IF NOT EXISTS (SELECT 1 FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = v_study_id) THEN
        INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) 
        VALUES (v_study_id, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASELINE', 1);
    END IF;
    SELECT study_event_definition_id INTO v_sed_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = v_study_id LIMIT 1;

    -- Clean up any pre-existing injection to guarantee fresh state
    DELETE FROM event_definition_crf WHERE crf_id = 99000;
    DELETE FROM item_form_metadata WHERE crf_version_id = 99000;
    DELETE FROM item_group_metadata WHERE crf_version_id = 99000;
    DELETE FROM response_set WHERE version_id = 99000;
    DELETE FROM item_data WHERE item_id IN (99001, 99002, 99003);
    DELETE FROM item WHERE item_id IN (99001, 99002, 99003);
    DELETE FROM item_group WHERE item_group_id = 99000;
    DELETE FROM section WHERE section_id = 99000;
    DELETE FROM event_crf WHERE crf_version_id = 99000;
    DELETE FROM crf_version WHERE crf_version_id = 99000;
    DELETE FROM crf WHERE crf_id = 99000;

    -- Insert CRF hierarchy
    INSERT INTO crf (crf_id, status_id, name, description, owner_id, date_created, oc_oid, source_study_id)
    VALUES (99000, 1, 'Central Review Uploads', 'CRF for central review file uploads', 1, NOW(), 'F_CENTRALREVI_99000', v_study_id);

    INSERT INTO crf_version (crf_version_id, crf_id, name, description, status_id, date_created, owner_id, oc_oid)
    VALUES (99000, 99000, 'v1.0', 'Initial Release', 1, NOW(), 1, 'v1.0_99000');

    INSERT INTO section (section_id, crf_version_id, status_id, label, title, ordinal, owner_id, date_created)
    VALUES (99000, 99000, 1, 'Main', 'Uploads', 1, 1, NOW());

    INSERT INTO item_group (item_group_id, name, crf_id, status_id, date_created, owner_id, oc_oid)
    VALUES (99000, 'IG_UPLOADS', 99000, 1, NOW(), 1, 'IG_UPLOADS_99000');

    -- Insert Items
    INSERT INTO item (item_id, name, description, item_data_type_id, status_id, owner_id, date_created, oc_oid)
    VALUES (99001, 'DOC_TYPE', 'Document Type', v_dt_string, 1, 1, NOW(), 'I_CENTR_DOC_TYPE');
    INSERT INTO item (item_id, name, description, item_data_type_id, status_id, owner_id, date_created, oc_oid)
    VALUES (99002, 'FILE_ATTACH', 'File Attachment', v_dt_file, 1, 1, NOW(), 'I_CENTR_FILE_ATTACH');
    INSERT INTO item (item_id, name, description, item_data_type_id, status_id, owner_id, date_created, oc_oid)
    VALUES (99003, 'COMMENTS', 'Comments', v_dt_string, 1, 1, NOW(), 'I_CENTR_COMMENTS');

    -- Insert Response Sets
    INSERT INTO response_set (response_set_id, response_type_id, label, options_text, options_values, version_id)
    VALUES (99001, v_rt_single, 'DocTypes', 'ECG,Lab Report,Imaging', 'ECG,Lab Report,Imaging', 99000);
    INSERT INTO response_set (response_set_id, response_type_id, label, options_text, options_values, version_id)
    VALUES (99002, v_rt_file, 'FileRes', 'File', 'file', 99000);
    INSERT INTO response_set (response_set_id, response_type_id, label, options_text, options_values, version_id)
    VALUES (99003, v_rt_text, 'TextRes', 'Text', 'text', 99000);

    -- Insert Item Form Metadata
    INSERT INTO item_form_metadata (item_form_metadata_id, item_id, crf_version_id, left_item_text, response_set_id, section_id, ordinal, required, status_id)
    VALUES (99001, 99001, 99000, 'Document Type:', 99001, 99000, 1, false, 1);
    INSERT INTO item_form_metadata (item_form_metadata_id, item_id, crf_version_id, left_item_text, response_set_id, section_id, ordinal, required, status_id)
    VALUES (99002, 99002, 99000, 'File Attachment:', 99002, 99000, 2, false, 1);
    INSERT INTO item_form_metadata (item_form_metadata_id, item_id, crf_version_id, left_item_text, response_set_id, section_id, ordinal, required, status_id)
    VALUES (99003, 99003, 99000, 'Comments:', 99003, 99000, 3, false, 1);

    -- Insert Item Group Metadata
    INSERT INTO item_group_metadata (item_group_metadata_id, item_group_id, crf_version_id, item_id, ordinal, borders, show_group)
    VALUES (99001, 99000, 99000, 99001, 1, 0, true);
    INSERT INTO item_group_metadata (item_group_metadata_id, item_group_id, crf_version_id, item_id, ordinal, borders, show_group)
    VALUES (99002, 99000, 99000, 99002, 2, 0, true);
    INSERT INTO item_group_metadata (item_group_metadata_id, item_group_id, crf_version_id, item_id, ordinal, borders, show_group)
    VALUES (99003, 99000, 99000, 99003, 3, 0, true);

    -- Link CRF to Baseline Assessment Event
    INSERT INTO event_definition_crf (event_definition_crf_id, study_event_definition_id, study_id, crf_id, required_crf, double_entry, default_version_id, status_id, owner_id, date_created)
    VALUES (99000, v_sed_id, v_study_id, 99000, false, false, 99000, 1, 1, NOW());

    -- Ensure subjects DM-101 and DM-102 have the Baseline Assessment scheduled
    SELECT study_subject_id INTO v_ss_101 FROM study_subject WHERE label = 'DM-101' AND study_id = v_study_id LIMIT 1;
    SELECT study_subject_id INTO v_ss_102 FROM study_subject WHERE label = 'DM-102' AND study_id = v_study_id LIMIT 1;

    IF v_ss_101 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM study_event WHERE study_subject_id = v_ss_101 AND study_event_definition_id = v_sed_id) THEN
        INSERT INTO study_event (study_subject_id, study_event_definition_id, start_date, status_id, owner_id, date_created, sample_ordinal)
        VALUES (v_ss_101, v_sed_id, NOW(), 1, 1, NOW(), 1);
    END IF;

    IF v_ss_102 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM study_event WHERE study_subject_id = v_ss_102 AND study_event_definition_id = v_sed_id) THEN
        INSERT INTO study_event (study_subject_id, study_event_definition_id, start_date, status_id, owner_id, date_created, sample_ordinal)
        VALUES (v_ss_102, v_sed_id, NOW(), 1, 1, NOW(), 1);
    END IF;

END $$;
EOF

docker exec -i oc-postgres psql -U clinica openclinica < /tmp/setup_crf.sql
echo "CRF injection completed."

# 3. Clean up any attached files from previous runs in the Tomcat container
echo "Cleaning up Tomcat attached files..."
docker exec oc-app find /usr/local/tomcat/openclinica_data/attached_files -name "*DM-101_ECG.pdf*" -delete 2>/dev/null || true
docker exec oc-app find /usr/local/tomcat/openclinica_data/attached_files -name "*DM-102_LabReport.pdf*" -delete 2>/dev/null || true

# 4. Record baseline audit log to detect GUI interaction
date +%s > /tmp/task_start_time
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

# 5. Launch and prepare OpenClinica UI
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="