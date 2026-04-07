#!/bin/bash
echo "=== Setting up occupational_antineoplastic_exposure_protocol task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Ana Isabel Betz ---
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ANA_PATIENT_ID" ]; then
    echo "FATAL: Patient Ana Isabel Betz not found in demo database. Aborting."
    exit 1
fi
echo "Ana Isabel Betz patient_id: $ANA_PATIENT_ID"
echo "$ANA_PATIENT_ID" > /tmp/antineo_target_patient_id
chmod 666 /tmp/antineo_target_patient_id 2>/dev/null || true

# --- 2. Ensure lab test types exist ---
echo "Ensuring required lab test types exist..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC' OR UPPER(name) LIKE '%COMPLETE BLOOD COUNT%');
    
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'COMPREHENSIVE METABOLIC PANEL', 'CMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CMP' OR UPPER(name) LIKE '%COMPREHENSIVE METABOLIC%');
    
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'HEPATIC FUNCTION PANEL', 'HEPATIC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'HEPATIC' OR UPPER(name) LIKE '%HEPATIC FUNCTION%');
    
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'RENAL FUNCTION PANEL', 'RENAL', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'RENAL' OR UPPER(name) LIKE '%RENAL FUNCTION%');
" 2>/dev/null || true

# --- 3. Contamination injection: T45.1 on Roberto Carlos ---
echo "Injecting contamination on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    T45_PATHOLOGY_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T45%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T45_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_disease WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $T45_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease), $ROBERTO_PATIENT_ID, $T45_PATHOLOGY_ID, true, 1, NOW(), 1, NOW())
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing Z57/T45 records and recent evaluations for Ana ---
echo "Cleaning pre-existing exposure and recent evaluation records for Ana..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $ANA_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'Z57%' OR code LIKE 'T45%')
" 2>/dev/null || true

TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $ANA_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/antineo_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/antineo_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/antineo_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/antineo_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/antineo_baseline_appt_max
for f in /tmp/antineo_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/antineo_task_start_date
chmod 666 /tmp/antineo_task_start_date 2>/dev/null || true

# --- 6. Setup UI ---
ensure_gnuhealth_logged_in
sleep 2

take_screenshot /tmp/task_initial_state.png
echo "=== Task setup complete ==="