#!/bin/bash
echo "=== Setting up occupational_benzene_hematotoxicity task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# --- 1. Find target patient John Zenon ---
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
echo "$JOHN_PATIENT_ID" > /tmp/benz_target_patient_id
chmod 666 /tmp/benz_target_patient_id 2>/dev/null || true

# --- 2. Ensure Hematology lab test types exist ---
for lab in "COMPLETE BLOOD COUNT|CBC" "HEMOGLOBIN|HGB" "PLATELET COUNT|PLT" "RETICULOCYTE COUNT|RETIC" "COMPREHENSIVE METABOLIC PANEL|CMP"; do
    NAME=$(echo "$lab" | cut -d'|' -f1)
    CODE=$(echo "$lab" | cut -d'|' -f2)
    gnuhealth_db_query "
        INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
        SELECT
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
            '$NAME', '$CODE', true, 1, NOW(), 1, NOW()
        WHERE NOT EXISTS (
            SELECT 1 FROM gnuhealth_lab_test_type WHERE code = '$CODE' OR UPPER(name) LIKE '%$NAME%'
        );
    " 2>/dev/null || true
done
echo "Ensured requisite hematology lab test types are available."

# --- 3. Contamination: Inject Benzene Toxicity on Ana Betz (wrong patient) ---
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    T52_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T52%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T52_ID" ]; then
        gnuhealth_db_query "
            INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
            SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease), $ANA_PATIENT_ID, $T52_ID, true, 1, NOW(), 1, NOW()
            WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_patient_disease WHERE patient = $ANA_PATIENT_ID AND pathology = $T52_ID);
        " 2>/dev/null || true
    fi
fi

# --- 4. Clean pre-existing target diseases and evaluations for John ---
echo "Cleaning pre-existing target records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T52%' OR code LIKE 'D61%')
" 2>/dev/null || true

TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record Baseline Max IDs ---
echo "Recording baseline state..."
echo "$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')" > /tmp/benz_baseline_disease_max
echo "$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')" > /tmp/benz_baseline_eval_max
echo "$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')" > /tmp/benz_baseline_prescription_max
echo "$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')" > /tmp/benz_baseline_lab_max
echo "$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')" > /tmp/benz_baseline_appt_max
date +%Y-%m-%d > /tmp/benz_task_start_date

chmod 666 /tmp/benz_* 2>/dev/null || true

# --- 6. Open App and Ensure Login ---
echo "Opening GNU Health in Firefox..."
ensure_gnuhealth_logged_in "http://localhost:8000/"

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="