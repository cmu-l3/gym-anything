#!/bin/bash
echo "=== Setting up occupational_corneal_foreign_body task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Matt Zenon ---
MATT_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Matt%' AND (pp.lastname IS NULL OR pp.lastname ILIKE '%Zenon%' OR pp.lastname ILIKE '%Betz%')
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$MATT_PATIENT_ID" ]; then
    MATT_PATIENT_ID=$(gnuhealth_db_query "
        SELECT gp.id
        FROM gnuhealth_patient gp
        JOIN party_party pp ON gp.party = pp.id
        WHERE CONCAT(COALESCE(pp.name,''), ' ', COALESCE(pp.lastname,'')) ILIKE '%Matt%Zenon%'
        LIMIT 1" | tr -d '[:space:]')
fi

if [ -z "$MATT_PATIENT_ID" ]; then
    echo "FATAL: Patient 'Matt Zenon' not found in demo database. Aborting."
    exit 1
fi
echo "Matt Zenon patient_id: $MATT_PATIENT_ID"
echo "$MATT_PATIENT_ID" > /tmp/ocfb_target_patient_id
chmod 666 /tmp/ocfb_target_patient_id 2>/dev/null || true

# --- 2. Inject contamination: T15 injury on Ana Betz (wrong patient distractor) ---
echo "Injecting contamination: T15 diagnosis on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    T15_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T15%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T15_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $T15_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $T15_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 3. Clean pre-existing T15 records, modern evals, and modern rx for Matt ---
echo "Cleaning pre-existing T15 records for Matt Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $MATT_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T15%')
" 2>/dev/null || true

TODAY=$(date +%Y-%m-%d)
echo "Cleaning today's evaluations for Matt Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $MATT_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 4. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline eval max: $BASELINE_EVAL_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/ocfb_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/ocfb_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/ocfb_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/ocfb_baseline_appt_max
for f in /tmp/ocfb_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%s > /tmp/task_start_time
date +%Y-%m-%d > /tmp/ocfb_task_start_date
chmod 666 /tmp/task_start_time /tmp/ocfb_task_start_date 2>/dev/null || true

# --- 5. Start Application ---
# Warm-up Firefox and navigate to login
ensure_firefox_gnuhealth
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="