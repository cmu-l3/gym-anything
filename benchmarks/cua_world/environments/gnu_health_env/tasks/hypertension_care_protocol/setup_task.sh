#!/bin/bash
echo "=== Setting up hypertension_care_protocol task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Verify Roberto Carlos exists ---
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
echo "$ROBERTO_PATIENT_ID" > /tmp/htn_target_patient_id
chmod 666 /tmp/htn_target_patient_id 2>/dev/null || true

# --- 2. Add LIPID PANEL lab test type if not present ---
echo "Ensuring LIPID PANEL lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'LIPID PANEL',
        'LIPID',
        true,
        1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type
        WHERE code = 'LIPID' OR UPPER(name) LIKE '%LIPID%'
    );
" 2>/dev/null || true

# --- 3. Clean any pre-existing I10 disease record for Roberto Carlos (idempotency) ---
echo "Cleaning pre-existing I10 record for Roberto Carlos..."
PATHOLOGY_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_pathology WHERE code = 'I10' LIMIT 1" | tr -d '[:space:]')
echo "ICD-10 I10 pathology_id: ${PATHOLOGY_ID:-not_found}"
if [ -n "$PATHOLOGY_ID" ] && [ -n "$ROBERTO_PATIENT_ID" ]; then
    gnuhealth_db_query "
        DELETE FROM gnuhealth_patient_disease
        WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $PATHOLOGY_ID
    " 2>/dev/null || true
fi

# --- 4. Record baseline counts (using ID-based high-water marks) ---
echo "Recording baseline state..."

# Max IDs before task starts (used to detect NEW records)
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max_id: $BASELINE_DISEASE_MAX"
echo "Baseline prescription max_id: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline lab max_id: $BASELINE_LAB_MAX"
echo "Baseline appointment max_id: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/htn_baseline_disease_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/htn_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/htn_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/htn_baseline_appt_max
for f in /tmp/htn_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

# Record task start date
date +%Y-%m-%d > /tmp/htn_task_start_date
chmod 666 /tmp/htn_task_start_date 2>/dev/null || true

# --- 5. Ensure GNU Health is running ---
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

# --- 6. Login and navigate to GNU Health ---
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# --- 7. Take initial screenshot ---
take_screenshot /tmp/htn_initial_state.png

echo "=== hypertension_care_protocol setup complete ==="
echo "Target patient: Roberto Carlos (patient_id=$ROBERTO_PATIENT_ID)"
echo "Task: Create complete hypertension management protocol"
echo "  1. Add Essential Hypertension (ICD-10: I10) to conditions"
echo "  2. Order Lipid Panel lab test"
echo "  3. Prescribe Amlodipine 5mg once daily (Dr. Cordara)"
echo "  4. Schedule follow-up in 18-42 days with Dr. Cordara"
