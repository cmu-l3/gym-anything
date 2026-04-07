#!/bin/bash
echo "=== Setting up emergency_acute_presentation task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find patient Luna ---
LUNA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Luna%'
      AND (pp.lastname IS NULL OR TRIM(pp.lastname) = '' OR pp.lastname ILIKE '%Luna%')
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$LUNA_PATIENT_ID" ]; then
    # Try broader search
    LUNA_PATIENT_ID=$(gnuhealth_db_query "
        SELECT gp.id
        FROM gnuhealth_patient gp
        JOIN party_party pp ON gp.party = pp.id
        WHERE CONCAT(COALESCE(pp.name,''), ' ', COALESCE(pp.lastname,'')) ILIKE '%Luna%'
        LIMIT 1" | tr -d '[:space:]')
fi

if [ -z "$LUNA_PATIENT_ID" ]; then
    echo "FATAL: Patient 'Luna' not found in demo database. Aborting."
    exit 1
fi
echo "Luna patient_id: $LUNA_PATIENT_ID"
echo "$LUNA_PATIENT_ID" > /tmp/er_target_patient_id
chmod 666 /tmp/er_target_patient_id 2>/dev/null || true

# --- 2. Ensure CBC and CRP lab test types exist ---
echo "Ensuring CBC lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC' OR UPPER(name) LIKE '%COMPLETE BLOOD COUNT%'
    );
" 2>/dev/null || true

echo "Ensuring CRP lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 2 FROM gnuhealth_lab_test_type),
        'C-REACTIVE PROTEIN', 'CRP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CRP' OR UPPER(name) LIKE '%C-REACTIVE PROTEIN%'
    );
" 2>/dev/null || true

# --- 3. Remove any today's appointments for Luna (clean start) ---
echo "Removing any existing today's appointments for Luna..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_appointment
    WHERE patient = $LUNA_PATIENT_ID
      AND appointment_date::date = '$TODAY'
" 2>/dev/null || true

# --- 4. Remove any recent disease records for Luna (clean start for diagnosis check) ---
echo "Removing any recent K-code disease records for Luna..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $LUNA_PATIENT_ID
      AND pathology IN (
          SELECT id FROM gnuhealth_pathology WHERE code LIKE 'K%'
      )
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baselines..."
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')

echo "Baseline appt max: $BASELINE_APPT_MAX"
echo "Baseline eval max: $BASELINE_EVAL_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline disease max: $BASELINE_DISEASE_MAX"

echo "$BASELINE_APPT_MAX" > /tmp/er_baseline_appt_max
echo "$BASELINE_EVAL_MAX" > /tmp/er_baseline_eval_max
echo "$BASELINE_LAB_MAX" > /tmp/er_baseline_lab_max
echo "$BASELINE_DISEASE_MAX" > /tmp/er_baseline_disease_max
for f in /tmp/er_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/er_task_start_date
chmod 666 /tmp/er_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running ---
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5
take_screenshot /tmp/er_initial_state.png

echo "=== emergency_acute_presentation setup complete ==="
echo "Target patient: Luna (patient_id=$LUNA_PATIENT_ID)"
echo "Clinical scenario: Acute RLQ pain + fever + nausea (acute appendicitis presentation)"
echo "IMPORTANT: This is a very_hard task — the agent must determine:"
echo "  - Appropriate urgency for today's emergency appointment"
echo "  - Vital signs: fever (>=38.0C) and tachycardia (>=100 bpm)"
echo "  - At least 2 lab tests (CBC and CRP are appropriate)"
echo "  - Correct ICD-10 K-code diagnosis (appendicitis: K35/K37)"
echo "  - Short-term surgical consultation (within 7 days)"
