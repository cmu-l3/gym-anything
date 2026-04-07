#!/bin/bash
echo "=== Setting up import_clinical_data task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Wait for database to be fully accessible
sleep 2

# -----------------------------------------------------------------------------
# 1. Clean previous state and construct the CRF structure using a PL/pgSQL block
# -----------------------------------------------------------------------------
echo "Setting up Demographics Survey CRF in the database..."

cat > /tmp/setup_crf.sql << 'EOF'
DO $$
DECLARE
    v_study_id INT;
    v_crf_id INT;
    v_crf_ver_id INT;
    v_section_id INT;
    v_item_group_id INT;
    v_igm_id INT;
    v_rs_id INT;
    v_item_id INT;
    v_event_def_id INT;
    v_ss_id INT;
    v_study_event_id INT;
BEGIN
    -- Get DM Trial study_id
    SELECT study_id INTO v_study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1;
    IF v_study_id IS NULL THEN
        RAISE EXCEPTION 'DM Trial study not found';
    END IF;

    -- Cleanup any existing Demographics Survey to ensure a clean state
    SELECT crf_id INTO v_crf_id FROM crf WHERE oc_oid = 'F_DEMOGRAPHICS' LIMIT 1;
    IF v_crf_id IS NOT NULL THEN
        DELETE FROM item_data WHERE event_crf_id IN (SELECT event_crf_id FROM event_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = v_crf_id));
        DELETE FROM event_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = v_crf_id);
        DELETE FROM event_definition_crf WHERE crf_id = v_crf_id;
        DELETE FROM item_form_metadata WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = v_crf_id);
        DELETE FROM item_group_metadata WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = v_crf_id);
        DELETE FROM section WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = v_crf_id);
        DELETE FROM crf_version WHERE crf_id = v_crf_id;
        DELETE FROM item_group WHERE crf_id = v_crf_id;
        DELETE FROM crf WHERE crf_id = v_crf_id;
    END IF;

    -- Create CRF
    INSERT INTO crf (status_id, name, description, owner_id, date_created, oc_oid, source_study_id)
    VALUES (1, 'Demographics Survey', 'Patient demographics', 1, NOW(), 'F_DEMOGRAPHICS', v_study_id)
    RETURNING crf_id INTO v_crf_id;

    -- Create CRF Version
    INSERT INTO crf_version (crf_id, name, description, status_id, owner_id, date_created, oc_oid)
    VALUES (v_crf_id, 'v1', 'Initial', 1, 1, NOW(), 'F_DEMOGRAPHICS_V1')
    RETURNING crf_version_id INTO v_crf_ver_id;

    -- Create Section
    INSERT INTO section (crf_version_id, status_id, name, title, owner_id, date_created, ordinal, page_number_label)
    VALUES (v_crf_ver_id, 1, 'Main', 'Demographics', 1, NOW(), 1, '1')
    RETURNING section_id INTO v_section_id;

    -- Create Item Group
    INSERT INTO item_group (name, crf_id, status_id, owner_id, date_created, oc_oid)
    VALUES ('Ungrouped', v_crf_id, 1, 1, NOW(), 'IG_DEMO_UNGROUPED')
    RETURNING item_group_id INTO v_item_group_id;

    -- Create Item Group Metadata
    INSERT INTO item_group_metadata (item_group_id, crf_version_id, status_id, owner_id, date_created, repeating, show_group)
    VALUES (v_item_group_id, v_crf_ver_id, 1, 1, NOW(), false, true)
    RETURNING item_group_metadata_id INTO v_igm_id;

    -- Create Response Set (Text/String type)
    INSERT INTO response_set (response_type_id, label, options_text, options_values, version_id)
    VALUES (1, 'Text', 'text', 'text', v_crf_ver_id)
    RETURNING response_set_id INTO v_rs_id;

    -- Insert Items and link them to the form (item_data_type_id: 1=string, 6=integer, 7=float)
    -- Age
    INSERT INTO item (name, description, item_data_type_id, status_id, owner_id, date_created, oc_oid) VALUES ('Age', 'Age', 6, 1, 1, NOW(), 'I_DEMO_AGE') RETURNING item_id INTO v_item_id;
    INSERT INTO item_form_metadata (item_id, crf_version_id, status_id, owner_id, date_created, header, show_item, section_id, item_group_metadata_id, response_set_id) VALUES (v_item_id, v_crf_ver_id, 1, 1, NOW(), 'Age', true, v_section_id, v_igm_id, v_rs_id);

    -- Weight
    INSERT INTO item (name, description, item_data_type_id, status_id, owner_id, date_created, oc_oid) VALUES ('Weight', 'Weight', 7, 1, 1, NOW(), 'I_DEMO_WEIGHT_KG') RETURNING item_id INTO v_item_id;
    INSERT INTO item_form_metadata (item_id, crf_version_id, status_id, owner_id, date_created, header, show_item, section_id, item_group_metadata_id, response_set_id) VALUES (v_item_id, v_crf_ver_id, 1, 1, NOW(), 'Weight (kg)', true, v_section_id, v_igm_id, v_rs_id);

    -- Height
    INSERT INTO item (name, description, item_data_type_id, status_id, owner_id, date_created, oc_oid) VALUES ('Height', 'Height', 6, 1, 1, NOW(), 'I_DEMO_HEIGHT_CM') RETURNING item_id INTO v_item_id;
    INSERT INTO item_form_metadata (item_id, crf_version_id, status_id, owner_id, date_created, header, show_item, section_id, item_group_metadata_id, response_set_id) VALUES (v_item_id, v_crf_ver_id, 1, 1, NOW(), 'Height (cm)', true, v_section_id, v_igm_id, v_rs_id);

    -- Smoking Status
    INSERT INTO item (name, description, item_data_type_id, status_id, owner_id, date_created, oc_oid) VALUES ('Smoking Status', 'Smoking Status', 1, 1, 1, NOW(), 'I_DEMO_SMOKING_STATUS') RETURNING item_id INTO v_item_id;
    INSERT INTO item_form_metadata (item_id, crf_version_id, status_id, owner_id, date_created, header, show_item, section_id, item_group_metadata_id, response_set_id) VALUES (v_item_id, v_crf_ver_id, 1, 1, NOW(), 'Smoking Status', true, v_section_id, v_igm_id, v_rs_id);

    -- Diabetes Years
    INSERT INTO item (name, description, item_data_type_id, status_id, owner_id, date_created, oc_oid) VALUES ('Diabetes Years', 'Diabetes Years', 6, 1, 1, NOW(), 'I_DEMO_DIABETES_YEARS') RETURNING item_id INTO v_item_id;
    INSERT INTO item_form_metadata (item_id, crf_version_id, status_id, owner_id, date_created, header, show_item, section_id, item_group_metadata_id, response_set_id) VALUES (v_item_id, v_crf_ver_id, 1, 1, NOW(), 'Years Since Diagnosis', true, v_section_id, v_igm_id, v_rs_id);

    -- Get/Create Baseline Assessment Event Definition
    SELECT study_event_definition_id INTO v_event_def_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = v_study_id AND status_id != 3 LIMIT 1;
    IF v_event_def_id IS NULL THEN
        INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal)
        VALUES (v_study_id, 'Baseline Assessment', 'Baseline', false, 'Scheduled', 1, 1, NOW(), 'SE_BASELINE', 1)
        RETURNING study_event_definition_id INTO v_event_def_id;
    END IF;

    -- Link CRF to Event
    INSERT INTO event_definition_crf (study_event_definition_id, crf_id, default_version_id, required_crf, status_id, owner_id, date_created)
    VALUES (v_event_def_id, v_crf_id, v_crf_ver_id, true, 1, 1, NOW());

    -- Ensure Subject DM-101 is enrolled and has event scheduled
    SELECT study_subject_id INTO v_ss_id FROM study_subject WHERE label = 'DM-101' AND study_id = v_study_id AND status_id != 3 LIMIT 1;
    IF v_ss_id IS NOT NULL THEN
        SELECT study_event_id INTO v_study_event_id FROM study_event WHERE study_subject_id = v_ss_id AND study_event_definition_id = v_event_def_id LIMIT 1;
        IF v_study_event_id IS NULL THEN
            INSERT INTO study_event (study_subject_id, study_event_definition_id, status_id, owner_id, date_created, start_date, subject_event_status_id)
            VALUES (v_ss_id, v_event_def_id, 1, 1, NOW(), CURRENT_DATE, 1);
        END IF;
    END IF;
END $$;
EOF

docker exec oc-postgres psql -U clinica openclinica -f /tmp/setup_crf.sql
echo "CRF setup script executed."

# -----------------------------------------------------------------------------
# 2. Retrieve OIDs to construct the ODM XML file dynamically
# -----------------------------------------------------------------------------
STUDY_OID=$(oc_query "SELECT oc_oid FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
SUBJ_OID=$(oc_query "SELECT su.oc_oid FROM subject su JOIN study_subject ss ON su.subject_id = ss.subject_id JOIN study st ON ss.study_id = st.study_id WHERE ss.label = 'DM-101' AND st.unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
EVENT_OID=$(oc_query "SELECT oc_oid FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = (SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024') LIMIT 1")

echo "Generating CDISC ODM XML with OIDs:"
echo "Study OID: $STUDY_OID"
echo "Subject OID: $SUBJ_OID"
echo "Event OID: $EVENT_OID"

XML_TIMESTAMP=$(date -Iseconds)
cat > /home/ga/import_data.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<ODM xmlns="http://www.cdisc.org/ns/odm/v1.3" FileType="Snapshot" FileOID="F.IMPORT.1" CreationDateTime="${XML_TIMESTAMP}" ODMVersion="1.3">
  <ClinicalData StudyOID="${STUDY_OID}" MetaDataVersionOID="v1.0.0">
    <SubjectData SubjectKey="${SUBJ_OID}">
      <StudyEventData StudyEventOID="${EVENT_OID}">
        <FormData FormOID="F_DEMOGRAPHICS">
          <ItemGroupData ItemGroupOID="IG_DEMO_UNGROUPED" ItemGroupRepeatKey="1" TransactionType="Insert">
            <ItemData ItemOID="I_DEMO_AGE" Value="56"/>
            <ItemData ItemOID="I_DEMO_WEIGHT_KG" Value="82.5"/>
            <ItemData ItemOID="I_DEMO_HEIGHT_CM" Value="168"/>
            <ItemData ItemOID="I_DEMO_SMOKING_STATUS" Value="Former"/>
            <ItemData ItemOID="I_DEMO_DIABETES_YEARS" Value="8"/>
          </ItemGroupData>
        </FormData>
      </StudyEventData>
    </SubjectData>
  </ClinicalData>
</ODM>
EOF

chown ga:ga /home/ga/import_data.xml
chmod 644 /home/ga/import_data.xml
echo "ODM XML file created at /home/ga/import_data.xml"

# -----------------------------------------------------------------------------
# 3. Record baseline metrics
# -----------------------------------------------------------------------------
INITIAL_ITEM_DATA_COUNT=$(oc_query "SELECT COUNT(*) FROM item_data")
echo "${INITIAL_ITEM_DATA_COUNT:-0}" > /tmp/initial_item_data_count

AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

NONCE=$(generate_result_nonce)
echo "Generated nonce: $NONCE"

# -----------------------------------------------------------------------------
# 4. Browser Setup
# -----------------------------------------------------------------------------
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

echo "=== import_clinical_data setup complete ==="