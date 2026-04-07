#!/bin/bash
echo "=== Setting up record_prenatal_care task ==="

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
echo "$ANA_PATIENT_ID" > /tmp/prenatal_target_patient_id
chmod 666 /tmp/prenatal_target_patient_id 2>/dev/null || true

# --- 2. Calculate and store target dates ---
TODAY=$(date +%Y-%m-%d)
TARGET_LMP=$(date -d "70 days ago" +%Y-%m-%d)
echo "Today: $TODAY"
echo "Target LMP (70 days ago): $TARGET_LMP"
echo "$TARGET_LMP" > /tmp/prenatal_target_lmp
chmod 666 /tmp/prenatal_target_lmp 2>/dev/null || true

# --- 3. Ensure prenatal lab test types exist ---
echo "Ensuring prenatal lab test types exist..."
for LAB in "URINALYSIS|URI" "COMPLETE BLOOD COUNT|CBC" "GLUCOSE TOLERANCE|OGTT" "BLOOD TYPE AND RH|TYPE_RH" "RUBELLA ANTIBODIES|RUBELLA"; do
    NAME="${LAB%%|*}"
    CODE="${LAB##*|}"
    gnuhealth_db_query "
        INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
        SELECT
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
            '$NAME', '$CODE', true, 1, NOW(), 1, NOW()
        WHERE NOT EXISTS (
            SELECT 1 FROM gnuhealth_lab_test_type WHERE code = '$CODE' OR UPPER(name) LIKE '%${NAME}%'
        );
    " 2>/dev/null || true
done

# --- 4. Contamination: Urinalysis lab order on Roberto Carlos (wrong patient) ---
echo "Injecting contamination: Urinalysis on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    URI_LAB_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_lab_test_type WHERE code = 'URI' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$URI_LAB_ID" ]; then
        gnuhealth_db_query "
            INSERT INTO gnuhealth_patient_lab_test (id, patient_id, test_type, date, state, create_uid, create_date, write_uid, write_date)
            VALUES (
                (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_lab_test),
                $ROBERTO_PATIENT_ID, $URI_LAB_ID, NOW(), 'draft', 1, NOW(), 1, NOW()
            )
        " 2>/dev/null || true
    fi
fi

# --- 5. Clean pre-existing pregnancy records for Ana ---
echo "Cleaning pre-existing pregnancy/evaluation records for Ana..."
# Evaluations
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_prenatal_evaluation
    WHERE name IN (SELECT id FROM gnuhealth_patient_pregnancy WHERE name = $ANA_PATIENT_ID)
" 2>/dev/null || true
# Pregnancies
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_pregnancy
    WHERE name = $ANA_PATIENT_ID
" 2>/dev/null || true

# --- 6. Record baselines ---
echo "Recording baseline state..."
BASELINE_PREG_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_pregnancy" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_prenatal_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline pregnancy max: $BASELINE_PREG_MAX"
echo "Baseline evaluation max: $BASELINE_EVAL_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline appointment max: $BASELINE_APPT_MAX"

echo "$BASELINE_PREG_MAX" > /tmp/prenatal_baseline_preg_max
echo "$BASELINE_EVAL_MAX" > /tmp/prenatal_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/prenatal_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/prenatal_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/prenatal_baseline_appt_max
for f in /tmp/prenatal_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%s > /tmp/task_start_time
date +%Y-%m-%d > /tmp/prenatal_task_start_date
chmod 666 /tmp/task_start_time /tmp/prenatal_task_start_date 2>/dev/null || true

# --- 7. Ensure GNU Health web interface is ready ---
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"

# Capture initial screenshot
echo "Capturing initial screenshot..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="