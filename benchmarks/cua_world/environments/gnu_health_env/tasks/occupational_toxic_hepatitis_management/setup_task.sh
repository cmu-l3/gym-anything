#!/bin/bash
echo "=== Setting up occupational_toxic_hepatitis_management task ==="

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
echo "$JOHN_PATIENT_ID" > /tmp/hep_target_patient_id
chmod 666 /tmp/hep_target_patient_id 2>/dev/null || true

# --- 2. Ensure Hepatic Lab Test Types exist ---
for test_name in "ALT (SGPT)" "AST (SGOT)" "BILIRUBIN" "ALKALINE PHOSPHATASE" "GAMMA GLUTAMYL TRANSFERASE"; do
    code=$(echo "$test_name" | awk '{print $1}' | cut -c1-4)
    echo "Ensuring $test_name lab test type exists..."
    gnuhealth_db_query "
        INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
        SELECT 
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
            '$test_name', '${code}_HEP', true, 1, NOW(), 1, NOW()
        WHERE NOT EXISTS (
            SELECT 1 FROM gnuhealth_lab_test_type WHERE name ILIKE '%$test_name%'
        );
    " 2>/dev/null || true
done

# --- 3. Contamination: K71 Toxic liver disease on Roberto Carlos (wrong patient) ---
echo "Injecting contamination: K71 Toxic liver disease on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    K71_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'K71%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$K71_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease 
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $K71_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $K71_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing K71 records and solvent allergies for John ---
echo "Cleaning pre-existing K71 disease records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease 
    WHERE patient = $JOHN_PATIENT_ID 
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'K71%')
" 2>/dev/null || true

echo "Cleaning pre-existing solvent allergy records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_allergy 
    WHERE patient = $JOHN_PATIENT_ID 
      AND (LOWER(allergen) LIKE '%toluene%' OR LOWER(allergen) LIKE '%carbon%' 
           OR LOWER(allergen) LIKE '%solvent%' OR LOWER(allergen) LIKE '%degreaser%')
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_ALLERGY_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_allergy" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/hep_baseline_disease_max
echo "$BASELINE_ALLERGY_MAX" > /tmp/hep_baseline_allergy_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/hep_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/hep_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/hep_baseline_appt_max
for f in /tmp/hep_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/hep_task_start_date
chmod 666 /tmp/hep_task_start_date 2>/dev/null || true

# --- 6. Configure Firefox / UI ---
ensure_gnuhealth_logged_in "http://localhost:8000/#menu_id=106&action_id=113"

# Take initial screenshot
take_screenshot /tmp/hep_initial_state.png

echo "=== Setup Complete ==="