#!/bin/bash
echo "=== Setting up occupational_contact_dermatitis task ==="

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
echo "$JOHN_PATIENT_ID" > /tmp/occ_derm_target_patient_id
chmod 666 /tmp/occ_derm_target_patient_id 2>/dev/null || true

# --- 2. Ensure required ICD-10 codes exist ---
echo "Ensuring L23 and L24 codes exist..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_pathology (id, code, name, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_pathology), 'L23', 'Allergic contact dermatitis', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_pathology WHERE code = 'L23');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_pathology (id, code, name, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_pathology), 'L24', 'Irritant contact dermatitis', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_pathology WHERE code = 'L24');
" 2>/dev/null || true

# --- 3. Contamination: L23 diagnosis and resin allergy on Ana Betz (distractor) ---
echo "Injecting contamination on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    L23_PATHOLOGY_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code = 'L23' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$L23_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_disease WHERE patient = $ANA_PATIENT_ID AND pathology = $L23_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease), $ANA_PATIENT_ID, $L23_PATHOLOGY_ID, true, 1, NOW(), 1, NOW())
            " 2>/dev/null || true
        fi
    fi
    
    EXISTING_ALLERGY=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_allergy WHERE patient = $ANA_PATIENT_ID AND LOWER(allergen) LIKE '%resin%'" | tr -d '[:space:]')
    if [ "${EXISTING_ALLERGY:-0}" -eq 0 ]; then
        gnuhealth_db_query "
            INSERT INTO gnuhealth_patient_allergy (id, patient, allergen, severity, create_uid, create_date, write_uid, write_date)
            VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_allergy), $ANA_PATIENT_ID, 'Industrial Resin', 'severe', 1, NOW(), 1, NOW())
        " 2>/dev/null || true
    fi
fi

# --- 4. Clean pre-existing task-related records for John Zenon ---
echo "Cleaning pre-existing dermatitis and allergy records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'L23%' OR code LIKE 'L24%')
" 2>/dev/null || true

gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_allergy
    WHERE patient = $JOHN_PATIENT_ID
" 2>/dev/null || true

TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_ALLERGY_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_allergy" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/occ_derm_baseline_disease_max
echo "$BASELINE_ALLERGY_MAX" > /tmp/occ_derm_baseline_allergy_max
echo "$BASELINE_EVAL_MAX" > /tmp/occ_derm_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/occ_derm_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/occ_derm_baseline_appt_max
for f in /tmp/occ_derm_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/occ_derm_task_start_date
chmod 666 /tmp/occ_derm_task_start_date 2>/dev/null || true

# --- 6. Start UI ---
echo "Starting Firefox and ensuring login..."
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"
sleep 2

take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="