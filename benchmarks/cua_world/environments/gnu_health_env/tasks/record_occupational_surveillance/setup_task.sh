#!/bin/bash
echo "=== Setting up record_occupational_surveillance task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find John Zenon ---
TARGET_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%John%' AND pp.lastname ILIKE '%Zenon%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$TARGET_PATIENT_ID" ]; then
    echo "FATAL: Patient John Zenon not found in demo database. Aborting."
    exit 1
fi
echo "John Zenon patient_id: $TARGET_PATIENT_ID"
echo "$TARGET_PATIENT_ID" > /tmp/surv_target_patient_id
chmod 666 /tmp/surv_target_patient_id 2>/dev/null || true

TARGET_PARTY_ID=$(gnuhealth_db_query "
    SELECT gp.party FROM gnuhealth_patient gp WHERE gp.id = $TARGET_PATIENT_ID LIMIT 1" | tr -d '[:space:]')
echo "$TARGET_PARTY_ID" > /tmp/surv_target_party_id
chmod 666 /tmp/surv_target_party_id 2>/dev/null || true

# --- 2. Ensure basic lab test types exist for the panel ---
echo "Ensuring required lab test types exist..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'HEPATIC FUNCTION PANEL', 'HEPATIC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'HEPATIC' OR UPPER(name) LIKE '%HEPATIC%' OR UPPER(name) LIKE '%LIVER%'
    );
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'RENAL FUNCTION PANEL', 'RENAL', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'RENAL' OR UPPER(name) LIKE '%RENAL%' OR UPPER(name) LIKE '%KIDNEY%'
    );
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC' OR UPPER(name) LIKE '%COMPLETE BLOOD COUNT%'
    );
" 2>/dev/null || true

# --- 3. Contamination: Z57 occupational exposure on Roberto Carlos (wrong patient) ---
echo "Injecting contamination: Z57 exposure on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    Z57_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'Z57%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$Z57_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $Z57_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $Z57_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing Z57 records and lifestyle records for John Zenon ---
echo "Cleaning pre-existing Z57 records for John..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'Z57%')
" 2>/dev/null || true

echo "Cleaning pre-existing lifestyle records for John..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lifestyle
    WHERE patient_lifestyle = $TARGET_PATIENT_ID
" 2>/dev/null || true
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lifestyle
    WHERE patient = $TARGET_PATIENT_ID
" 2>/dev/null || true

# --- 5. Record baselines for anti-gaming ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_LIFESTYLE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lifestyle" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/surv_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/surv_baseline_eval_max
echo "$BASELINE_LAB_MAX" > /tmp/surv_baseline_lab_max
echo "$BASELINE_LIFESTYLE_MAX" > /tmp/surv_baseline_lifestyle_max
echo "$BASELINE_APPT_MAX" > /tmp/surv_baseline_appt_max
for f in /tmp/surv_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/surv_task_start_date
chmod 666 /tmp/surv_task_start_date 2>/dev/null || true

# Start/Ensure GNU Health UI
echo "Warming up GNU Health UI..."
ensure_firefox_gnuhealth
take_screenshot /tmp/surv_initial_state.png

echo "=== Task Setup Complete ==="