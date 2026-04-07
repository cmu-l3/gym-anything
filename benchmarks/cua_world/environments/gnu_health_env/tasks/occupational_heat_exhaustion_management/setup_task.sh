#!/bin/bash
echo "=== Setting up occupational_heat_exhaustion_management task ==="

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
echo "$JOHN_PATIENT_ID" > /tmp/heat_target_patient_id
chmod 666 /tmp/heat_target_patient_id 2>/dev/null || true

# --- 2. Ensure metabolic lab test types exist ---
echo "Ensuring relevant lab test types exist..."
LABS=(
    "BASIC METABOLIC PANEL|BMP"
    "COMPREHENSIVE METABOLIC PANEL|CMP"
    "SERUM ELECTROLYTES|ELEC"
    "SERUM CREATININE|CREAT"
    "URINALYSIS|UA"
)

for LAB_DEF in "${LABS[@]}"; do
    L_NAME="${LAB_DEF%%|*}"
    L_CODE="${LAB_DEF##*|}"
    gnuhealth_db_query "
        INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
        SELECT
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
            '$L_NAME', '$L_CODE', true, 1, NOW(), 1, NOW()
        WHERE NOT EXISTS (
            SELECT 1 FROM gnuhealth_lab_test_type WHERE code = '$L_CODE' OR UPPER(name) LIKE '%${L_NAME}%'
        );
    " 2>/dev/null || true
done

# --- 3. Contamination: T67.0 diagnosis on Roberto Carlos (wrong patient) ---
echo "Injecting contamination: T67.0 on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    T67_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T67%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T67_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $T67_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $T67_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing T-code records and today's evaluations for John Zenon ---
echo "Cleaning pre-existing T-code disease records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for John Zenon from today..."
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
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline eval max: $BASELINE_EVAL_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/heat_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/heat_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/heat_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/heat_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/heat_baseline_appt_max
for f in /tmp/heat_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/heat_task_start_date
chmod 666 /tmp/heat_task_start_date 2>/dev/null || true
date +%s > /tmp/task_start_time.txt

# --- 6. Warm up Firefox ---
su - ga -c "DISPLAY=:1 firefox http://localhost:8000/ &"
sleep 5
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

take_screenshot /tmp/heat_initial_state.png

echo "=== Task setup complete ==="