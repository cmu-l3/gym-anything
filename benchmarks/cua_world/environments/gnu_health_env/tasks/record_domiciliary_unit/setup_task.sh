#!/bin/bash
echo "=== Setting up record_domiciliary_unit task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Bonifacio Caput ---
BONIFACIO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Bonifacio%' AND pp.lastname ILIKE '%Caput%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$BONIFACIO_PATIENT_ID" ]; then
    echo "FATAL: Patient Bonifacio Caput not found in demo database. Aborting."
    exit 1
fi
echo "Bonifacio Caput patient_id: $BONIFACIO_PATIENT_ID"
echo "$BONIFACIO_PATIENT_ID" > /tmp/du_target_patient_id
chmod 666 /tmp/du_target_patient_id 2>/dev/null || true

# --- 2. Ensure required lab test types exist ---
echo "Ensuring basic respiratory/baseline labs exist..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC');

    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'ARTERIAL BLOOD GAS', 'ABG', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'ABG');
" 2>/dev/null || true

# --- 3. Contamination: J44.9 COPD on Ana Betz (wrong patient) ---
echo "Injecting contamination: J44.9 COPD on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    J44_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'J44.9' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$J44_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $J44_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $J44_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Contamination: Decoy Domiciliary Unit ---
echo "Injecting contamination: Decoy Domiciliary Unit..."
EXISTING_DECOY=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_du WHERE name = 'DU-DISTRACTOR-001'" | tr -d '[:space:]')
if [ "${EXISTING_DECOY:-0}" -eq 0 ]; then
    gnuhealth_db_query "
        INSERT INTO gnuhealth_du (id, name, create_uid, create_date, write_uid, write_date)
        VALUES (
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_du),
            'DU-DISTRACTOR-001', 1, NOW(), 1, NOW()
        )
    " 2>/dev/null || true
fi

# --- 5. Clean pre-existing task state for Bonifacio Caput ---
echo "Cleaning pre-existing J44 diagnoses for Bonifacio..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $BONIFACIO_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J44%')
" 2>/dev/null || true

echo "Unlinking any existing DU from Bonifacio..."
gnuhealth_db_query "UPDATE gnuhealth_patient SET du = NULL WHERE id = $BONIFACIO_PATIENT_ID" 2>/dev/null || true

echo "Removing any pre-existing DU with name DU-CAPUT-001..."
gnuhealth_db_query "DELETE FROM gnuhealth_du WHERE name = 'DU-CAPUT-001'" 2>/dev/null || true

# --- 6. Record baselines ---
echo "Recording baseline state..."
BASELINE_DU_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_du" | tr -d '[:space:]')
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline DU max: $BASELINE_DU_MAX"
echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DU_MAX" > /tmp/du_baseline_max
echo "$BASELINE_DISEASE_MAX" > /tmp/du_baseline_disease_max
echo "$BASELINE_LAB_MAX" > /tmp/du_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/du_baseline_appt_max
for f in /tmp/du_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/du_task_start_date
chmod 666 /tmp/du_task_start_date 2>/dev/null || true

# --- 7. Ensure GNU Health is running in Firefox ---
echo "Setting up Firefox..."
ensure_gnuhealth_logged_in "http://localhost:8000/"
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="