#!/bin/bash
echo "=== Setting up wastewater_biohazard_protocol task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Bonifacio Caput ---
BONIFACIO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Bonifacio%' AND pp.lastname ILIKE '%Caput%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$BONIFACIO_PATIENT_ID" ]; then
    echo "FATAL: Patient Bonifacio Caput not found in demo database. Aborting."
    exit 1
fi
echo "Bonifacio Caput patient_id: $BONIFACIO_PATIENT_ID"
echo "$BONIFACIO_PATIENT_ID" > /tmp/ww_target_patient_id
chmod 666 /tmp/ww_target_patient_id 2>/dev/null || true

# --- 2. Ensure diagnostic lab test types exist ---
echo "Ensuring STOOL CULTURE lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'STOOL CULTURE', 'STOOL_CULT', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'STOOL_CULT' OR UPPER(name) LIKE '%STOOL CULTURE%'
    );
" 2>/dev/null || true

echo "Ensuring COMPREHENSIVE METABOLIC PANEL lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPREHENSIVE METABOLIC PANEL', 'CMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CMP' OR UPPER(name) LIKE '%COMPREHENSIVE METABOLIC%'
    );
" 2>/dev/null || true

echo "Ensuring COMPLETE BLOOD COUNT lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC' OR UPPER(name) LIKE '%COMPLETE BLOOD COUNT%'
    );
" 2>/dev/null || true

# --- 3. Contamination: A09 Gastroenteritis on Ana Betz (wrong patient distractor) ---
echo "Injecting contamination: A09 diagnosis on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    A09_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'A09%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$A09_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $A09_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $A09_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing A00-A09 records and evaluations for Bonifacio ---
echo "Cleaning pre-existing A00-A09 disease records for Bonifacio..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $BONIFACIO_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'A0%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for Bonifacio from today..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $BONIFACIO_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/ww_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/ww_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/ww_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/ww_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/ww_baseline_appt_max
for f in /tmp/ww_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/ww_task_start_date
chmod 666 /tmp/ww_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running & logged in ---
ensure_gnuhealth_logged_in "http://localhost:8000/#"

echo "=== Task Setup Complete ==="