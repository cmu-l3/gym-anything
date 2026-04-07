#!/bin/bash
echo "=== Setting up occupational_metal_fume_fever task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# --- 1. Find target patient (John Zenon) ---
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
echo "$JOHN_PATIENT_ID" > /tmp/mff_target_patient_id
chmod 666 /tmp/mff_target_patient_id 2>/dev/null || true

# --- 2. Ensure required lab test types exist ---
echo "Ensuring CHEST X-RAY test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'CHEST X-RAY (PA AND LATERAL)', 'CXR', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CXR' OR UPPER(name) LIKE '%CHEST X-RAY%' OR UPPER(name) LIKE '%CHEST RADIOGRAPH%'
    );
" 2>/dev/null || true

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

# --- 3. Inject contamination (T59 on Ana Betz to test agent targets correct patient) ---
echo "Injecting contamination: T59 (Toxic effect of gases) on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    T59_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T59%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T59_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $T59_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $T59_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing J68/T59 records and evaluations for John ---
echo "Cleaning pre-existing J68/T59 records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J68%' OR code LIKE 'T59%')
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

echo "$BASELINE_DISEASE_MAX" > /tmp/mff_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/mff_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/mff_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/mff_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/mff_baseline_appt_max
for f in /tmp/mff_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/mff_task_start_date
chmod 666 /tmp/mff_task_start_date 2>/dev/null || true

# Focus and maximize browser window if it exists
focus_firefox || true
sleep 1

echo "=== Task setup complete ==="