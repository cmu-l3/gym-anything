#!/bin/bash
echo "=== Setting up polypharmacy_deprescribing_review task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Roberto Carlos ---
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ROBERTO_PATIENT_ID" ]; then
    echo "FATAL: Patient Roberto Carlos not found in demo database. Aborting."
    exit 1
fi
echo "Roberto Carlos patient_id: $ROBERTO_PATIENT_ID"
echo "$ROBERTO_PATIENT_ID" > /tmp/poly_target_patient_id
chmod 666 /tmp/poly_target_patient_id 2>/dev/null || true

# --- 2. Ensure BMP lab test type exists ---
echo "Ensuring BMP lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'BASIC METABOLIC PANEL', 'BMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'BMP' OR UPPER(name) LIKE '%BASIC METABOLIC%'
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

# --- 3. Contamination: ACE inhibitor allergy on Ana Betz (wrong patient) ---
echo "Injecting contamination: ACE inhibitor allergy on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    EXISTING_CONTAM=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM gnuhealth_patient_allergy
        WHERE patient = $ANA_PATIENT_ID AND LOWER(allergen) LIKE '%enalapril%'" | tr -d '[:space:]')
    if [ "${EXISTING_CONTAM:-0}" -eq 0 ]; then
        gnuhealth_db_query "
            INSERT INTO gnuhealth_patient_allergy (id, patient, allergen, severity, create_uid, create_date, write_uid, write_date)
            VALUES (
                (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_allergy),
                $ANA_PATIENT_ID, 'Enalapril (ACE Inhibitor)', 'moderate', 1, NOW(), 1, NOW()
            )
        " 2>/dev/null || true
    fi
fi

# --- 4. Clean pre-existing fall/injury diagnoses and ACE allergy for Roberto ---
echo "Cleaning pre-existing W/S-code disease records for Roberto Carlos..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $ROBERTO_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'W%' OR code LIKE 'S%')
" 2>/dev/null || true

echo "Cleaning pre-existing ACE inhibitor allergy for Roberto Carlos..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_allergy
    WHERE patient = $ROBERTO_PATIENT_ID
      AND (LOWER(allergen) LIKE '%enalapril%' OR LOWER(allergen) LIKE '%ace%inhibitor%'
           OR LOWER(allergen) LIKE '%lisinopril%' OR LOWER(allergen) LIKE '%captopril%')
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_ALLERGY_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_allergy" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline allergy max: $BASELINE_ALLERGY_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/poly_baseline_disease_max
echo "$BASELINE_ALLERGY_MAX" > /tmp/poly_baseline_allergy_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/poly_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/poly_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/poly_baseline_appt_max
for f in /tmp/poly_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/poly_task_start_date
chmod 666 /tmp/poly_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running ---
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5
take_screenshot /tmp/poly_initial_state.png

echo "=== polypharmacy_deprescribing_review setup complete ==="
echo "Target patient: Roberto Carlos (patient_id=$ROBERTO_PATIENT_ID)"
echo "Clinical scenario: Fall-related medication safety review"
echo "IMPORTANT: This is a very_hard task — the agent must independently determine:"
echo "  - Appropriate fall-related ICD-10 code (W19, S-code, etc.)"
echo "  - How to document ACE inhibitor adverse drug reaction"
echo "  - Safer antihypertensive alternative (ARB/CCB/thiazide)"
echo "  - Post-fall laboratory workup (CBC, BMP/CMP)"
echo "  - Appropriate follow-up timing (7-21 days)"
