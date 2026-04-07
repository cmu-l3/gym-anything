#!/bin/bash
echo "=== Setting up occupational_hearing_conservation task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find John Zenon ---
JOHN_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%John%' AND pp.lastname ILIKE '%Zenon%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$JOHN_PATIENT_ID" ]; then
    echo "FATAL: Patient John Zenon not found in demo database. Aborting."
    exit 1
fi
echo "John Zenon patient_id: $JOHN_PATIENT_ID"
echo "$JOHN_PATIENT_ID" > /tmp/ohc_target_patient_id
chmod 666 /tmp/ohc_target_patient_id 2>/dev/null || true

# --- 2. Ensure metabolic lab test types exist ---
echo "Ensuring FASTING GLUCOSE lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'FASTING BLOOD GLUCOSE', 'FBG', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'FBG' OR UPPER(name) LIKE '%FASTING%GLUCOSE%'
    );
" 2>/dev/null || true

echo "Ensuring HBA1C lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'GLYCATED HEMOGLOBIN (HBA1C)', 'HBA1C', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'HBA1C' OR UPPER(name) LIKE '%HBA1C%'
    );
" 2>/dev/null || true

# --- 3. Contamination injection: Z57.0 noise exposure on Ana Betz (wrong patient) ---
echo "Injecting contamination: Z57.0 on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    Z57_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'Z57.0' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$Z57_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $Z57_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $Z57_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean any pre-existing Z57/H90 records or evaluations for John ---
echo "Cleaning pre-existing target disease records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'Z57%' OR code LIKE 'H90%')
" 2>/dev/null || true

# Clean any pre-existing evaluations for John from today
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline eval max: $BASELINE_EVAL_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/ohc_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/ohc_baseline_eval_max
echo "$BASELINE_LAB_MAX" > /tmp/ohc_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/ohc_baseline_appt_max
for f in /tmp/ohc_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/ohc_task_start_date
date +%s > /tmp/ohc_task_start_timestamp
chmod 666 /tmp/ohc_task_start_date /tmp/ohc_task_start_timestamp 2>/dev/null || true

# --- 6. Configure UI ---
echo "Configuring Firefox..."
ensure_firefox_gnuhealth
sleep 2

# Take initial screenshot
take_screenshot /tmp/ohc_task_initial.png ga

echo "=== Setup complete ==="