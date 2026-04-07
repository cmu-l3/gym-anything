#!/bin/bash
echo "=== Setting up commercial_driver_fitness_exam task ==="

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
echo "$JOHN_PATIENT_ID" > /tmp/fitness_target_patient_id
chmod 666 /tmp/fitness_target_patient_id 2>/dev/null || true

# --- 2. Contamination: High BP evaluation on Ana Betz (distractor) ---
echo "Injecting contamination: High BP evaluation on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    gnuhealth_db_query "
        INSERT INTO gnuhealth_patient_evaluation (id, patient, systolic, diastolic, create_uid, create_date, write_uid, write_date)
        VALUES (
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_evaluation),
            $ANA_PATIENT_ID, 180, 100, 1, NOW(), 1, NOW()
        )
    " 2>/dev/null || true
fi

# --- 3. Clean pre-existing records for John Zenon ---
echo "Cleaning pre-existing diagnoses and evaluations for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'I10%' OR code LIKE 'G47%')
" 2>/dev/null || true

TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 4. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline eval max: $BASELINE_EVAL_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/fitness_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/fitness_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/fitness_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/fitness_baseline_appt_max
for f in /tmp/fitness_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/fitness_task_start_date
chmod 666 /tmp/fitness_task_start_date 2>/dev/null || true

# --- 5. Ensure GNU Health is running and start Firefox ---
ensure_gnuhealth_logged_in "http://localhost:8000/#"

# Wait a moment for UI to stabilize, then take initial screenshot
sleep 3
take_screenshot /tmp/fitness_initial_state.png
echo "=== Task setup complete ==="