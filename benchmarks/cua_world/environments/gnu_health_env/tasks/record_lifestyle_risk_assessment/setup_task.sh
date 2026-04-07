#!/bin/bash
echo "=== Setting up record_lifestyle_risk_assessment task ==="

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
echo "$BONIFACIO_PATIENT_ID" > /tmp/lfa_target_patient_id
chmod 666 /tmp/lfa_target_patient_id 2>/dev/null || true

# Get party_id
BONIFACIO_PARTY_ID=$(gnuhealth_db_query "
    SELECT gp.party FROM gnuhealth_patient gp WHERE gp.id = $BONIFACIO_PATIENT_ID LIMIT 1" | tr -d '[:space:]')
echo "$BONIFACIO_PARTY_ID" > /tmp/lfa_target_party_id
chmod 666 /tmp/lfa_target_party_id 2>/dev/null || true

# --- 2. Ensure lab test types exist ---
echo "Ensuring URINALYSIS lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'URINALYSIS', 'UA', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'UA' OR UPPER(name) LIKE '%URINALYSIS%'
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

# --- 3. Distractor: F17 diagnosis on Roberto Carlos ---
echo "Injecting contamination: F17 diagnosis on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    F17_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'F17' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$F17_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $F17_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $F17_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing records for Bonifacio to ensure agent does the work ---
echo "Resetting Bonifacio's lifestyle to default healthy state..."
gnuhealth_db_query "
    UPDATE gnuhealth_patient 
    SET smoking = false, smoking_number = 0, exercise = true, alcohol = false, sleep_hours = 8 
    WHERE id = $BONIFACIO_PATIENT_ID
" 2>/dev/null || true

echo "Cleaning any pre-existing F17 records for Bonifacio..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $BONIFACIO_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'F17%')
" 2>/dev/null || true

echo "Cleaning pre-existing nicotine prescriptions for Bonifacio..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_prescription_order_line
    WHERE name IN (
        SELECT id FROM gnuhealth_prescription_order WHERE patient = $BONIFACIO_PATIENT_ID
    ) AND medicament IN (
        SELECT m.id FROM gnuhealth_medicament m
        JOIN product_product pp ON m.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE pt.name ILIKE '%nicotine%' OR pt.name ILIKE '%varenicline%' OR pt.name ILIKE '%bupropion%'
    )
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/lfa_baseline_disease_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/lfa_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/lfa_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/lfa_baseline_appt_max
for f in /tmp/lfa_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/lfa_task_start_date
date +%s > /tmp/task_start_time
chmod 666 /tmp/lfa_task_start_date /tmp/task_start_time 2>/dev/null || true

# --- 6. Warm up GNU Health / Firefox ---
echo "Warming up GNU Health in Firefox..."
su - ga -c "DISPLAY=:1 firefox http://localhost:8000/ &" > /dev/null 2>&1
sleep 5
wait_for_window "firefox\|mozilla" 30
focus_firefox
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/lfa_initial_state.png ga
echo "=== Setup complete ==="