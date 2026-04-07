#!/bin/bash
echo "=== Setting up record_occupational_rads task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find target patient Bonifacio Caput ---
TARGET_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Bonifacio%' AND pp.lastname ILIKE '%Caput%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$TARGET_PATIENT_ID" ]; then
    echo "FATAL: Patient Bonifacio Caput not found in database. Aborting."
    exit 1
fi
echo "Bonifacio Caput patient_id: $TARGET_PATIENT_ID"
echo "$TARGET_PATIENT_ID" > /tmp/rads_target_patient_id
chmod 666 /tmp/rads_target_patient_id 2>/dev/null || true

# --- 2. Ensure required lab test types exist ---
echo "Ensuring required lab test types exist (ABG, CXR, CBC, BMP)..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'ARTERIAL BLOOD GAS', 'ABG', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'ABG' OR UPPER(name) LIKE '%ARTERIAL BLOOD GAS%');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'CHEST X-RAY', 'CXR', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CXR' OR UPPER(name) LIKE '%CHEST X-RAY%');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC' OR UPPER(name) LIKE '%COMPLETE BLOOD COUNT%');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'BASIC METABOLIC PANEL', 'BMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'BMP' OR UPPER(name) LIKE '%BASIC METABOLIC%');
" 2>/dev/null || true

# --- 3. Contamination injection: J45.20 asthma on Ana Betz ---
echo "Injecting contamination: Asthma diagnosis on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    J45_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J45%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$J45_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $J45_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $J45_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing respiratory records for Bonifacio ---
echo "Cleaning pre-existing J-code diagnoses for Bonifacio..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J%')
" 2>/dev/null || true

# Clean evaluations from today to ensure fresh entry
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/rads_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/rads_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/rads_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/rads_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/rads_baseline_appt_max
for f in /tmp/rads_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/rads_task_start_date
chmod 666 /tmp/rads_task_start_date 2>/dev/null || true

# --- 6. Task initialization screenshot ---
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="