#!/bin/bash
echo "=== Setting up perioperative_appendectomy_management task ==="

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
echo "$LUNA_PATIENT_ID" > /tmp/appx_target_patient_id
chmod 666 /tmp/appx_target_patient_id 2>/dev/null || true

# --- 2. Ensure required lab test types exist ---
echo "Ensuring CMP lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPREHENSIVE METABOLIC PANEL', 'CMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CMP' OR UPPER(name) LIKE '%COMPREHENSIVE METABOLIC%'
    );
" 2>/dev/null || true

echo "Ensuring PT/INR coagulation test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'PROTHROMBIN TIME / INR', 'PT_INR', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'PT_INR' OR UPPER(name) LIKE '%PROTHROMBIN%' OR UPPER(name) LIKE '%PT/INR%'
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

# --- 3. Contamination injection: K29.x gastritis on Roberto Carlos ---
echo "Injecting contamination: gastritis diagnosis on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    K29_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'K29' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$K29_PATHOLOGY_ID" ]; then
        # Check if contamination already exists
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $K29_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $K29_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean any pre-existing K35 appendicitis records for Luna ---
echo "Cleaning pre-existing K35 records for Luna..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $LUNA_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'K35%')
" 2>/dev/null || true

# Clean any pre-existing evaluations for Luna from today
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $LUNA_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline eval max: $BASELINE_EVAL_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/appx_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/appx_baseline_eval_max
echo "$BASELINE_LAB_MAX" > /tmp/appx_baseline_lab_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/appx_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/appx_baseline_appt_max
for f in /tmp/appx_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/appx_task_start_date
chmod 666 /tmp/appx_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running ---
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5
take_screenshot /tmp/appx_initial_state.png

echo "=== perioperative_appendectomy_management setup complete ==="
echo "Target patient: Luna (patient_id=$LUNA_PATIENT_ID)"
echo "Clinical scenario: Acute appendicitis requiring perioperative management"
echo "IMPORTANT: This is a very_hard task — the agent must independently determine:"
echo "  - Correct ICD-10 code for acute appendicitis (K35.x)"
echo "  - Standard pre-operative lab panel (CBC, CMP, Coagulation)"
echo "  - Appropriate perioperative antibiotic prophylaxis"
echo "  - Clinical evaluation with appropriate vital signs"
echo "  - Post-discharge follow-up timing (7-14 days)"
