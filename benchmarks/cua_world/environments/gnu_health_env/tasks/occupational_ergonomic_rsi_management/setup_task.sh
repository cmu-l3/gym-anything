#!/bin/bash
echo "=== Setting up occupational_ergonomic_rsi_management task ==="

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
echo "$JOHN_PATIENT_ID" > /tmp/rsi_target_patient_id
chmod 666 /tmp/rsi_target_patient_id 2>/dev/null || true

# --- 2. Ensure diagnostic lab test type exists ---
echo "Ensuring WRIST X-RAY lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'WRIST X-RAY', 'XR_WRIST', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'XR_WRIST' OR UPPER(name) LIKE '%WRIST X-RAY%'
    );
" 2>/dev/null || true

# --- 3. Contamination: G56.0 Carpal Tunnel on Ana Betz (wrong patient) ---
echo "Injecting contamination: G56.0 Carpal Tunnel on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    G56_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'G56%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$G56_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $G56_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $G56_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing G-code records and evaluations for John ---
echo "Cleaning pre-existing G-code disease records for John..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'G%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for John from today..."
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

echo "$BASELINE_DISEASE_MAX" > /tmp/rsi_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/rsi_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/rsi_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/rsi_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/rsi_baseline_appt_max
for f in /tmp/rsi_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/rsi_task_start_date
chmod 666 /tmp/rsi_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running ---
echo "Warming up GNU Health in Firefox..."
ensure_firefox_gnuhealth
sleep 2
focus_firefox

# Take initial screenshot
take_screenshot /tmp/rsi_initial_state.png

echo "=== Setup complete ==="