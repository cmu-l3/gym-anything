#!/bin/bash
echo "=== Setting up abnormal_hba1c_management task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Ana Isabel Betz ---
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ANA_PATIENT_ID" ]; then
    echo "FATAL: Ana Isabel Betz not found. Aborting."
    exit 1
fi
echo "Ana Betz patient_id: $ANA_PATIENT_ID"
echo "$ANA_PATIENT_ID" > /tmp/hbac_target_patient_id
chmod 666 /tmp/hbac_target_patient_id 2>/dev/null || true

# --- 2. Ensure HbA1c lab test type exists ---
HBAC_TYPE_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_lab_test_type
    WHERE code = 'HBA1C' OR UPPER(name) LIKE '%HBA1C%' OR UPPER(name) LIKE '%GLYCATED%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$HBAC_TYPE_ID" ]; then
    echo "Adding HbA1c lab test type..."
    gnuhealth_db_query "
        INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
        SELECT
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
            'GLYCATED HEMOGLOBIN (HbA1c)', 'HBA1C', true, 1, NOW(), 1, NOW()
        WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'HBA1C');
    " 2>/dev/null || true
    HBAC_TYPE_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_lab_test_type WHERE code = 'HBA1C' LIMIT 1" | tr -d '[:space:]')
fi
echo "HbA1c lab type id: $HBAC_TYPE_ID"

# --- 3. Remove any existing pending HbA1c test for Ana (clean state) ---
echo "Cleaning old pending HbA1c tests for Ana Betz..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lab_test
    WHERE patient_id = $ANA_PATIENT_ID
      AND test_type = $HBAC_TYPE_ID
      AND (state = 'draft' OR state = 'requested' OR state IS NULL OR state = 'ordered')
" 2>/dev/null || true

# --- 4. Get healthprof id for Dr. Cordara ---
CORDARA_HP_ID=$(gnuhealth_db_query "
    SELECT hp.id FROM gnuhealth_healthprofessional hp
    JOIN party_party pp ON hp.party = pp.id
    WHERE pp.lastname ILIKE '%Cordara%' OR pp.name ILIKE '%Cordara%'
    LIMIT 1" | tr -d '[:space:]')
echo "Cordara health prof id: ${CORDARA_HP_ID:-not_found}"

# --- 5. Seed a pending HbA1c lab test for Ana Betz ---
echo "Creating pending HbA1c lab test for Ana Betz..."
NEW_LAB_ID=$(gnuhealth_db_query "
    INSERT INTO gnuhealth_patient_lab_test (
        patient_id, test_type, date_requested, state, create_uid, create_date, write_uid, write_date
        $([ -n "$CORDARA_HP_ID" ] && echo ', pathologist')
    )
    VALUES (
        $ANA_PATIENT_ID,
        $HBAC_TYPE_ID,
        NOW(),
        'requested',
        1, NOW(), 1, NOW()
        $([ -n "$CORDARA_HP_ID" ] && echo ", $CORDARA_HP_ID")
    )
    RETURNING id;
" 2>/dev/null | tr -d '[:space:]')

# Fallback if pathologist column fails
if [ -z "$NEW_LAB_ID" ]; then
    NEW_LAB_ID=$(gnuhealth_db_query "
        INSERT INTO gnuhealth_patient_lab_test (
            patient_id, test_type, date_requested, state, create_uid, create_date, write_uid, write_date
        )
        VALUES (
            $ANA_PATIENT_ID, $HBAC_TYPE_ID, NOW(), 'requested', 1, NOW(), 1, NOW()
        )
        RETURNING id;
    " 2>/dev/null | tr -d '[:space:]')
fi
echo "Seeded pending HbA1c lab test id: ${NEW_LAB_ID:-failed}"
echo "${NEW_LAB_ID:-0}" > /tmp/hbac_seeded_lab_id
chmod 666 /tmp/hbac_seeded_lab_id 2>/dev/null || true

# --- 6. Record baselines ---
echo "Recording baselines..."
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

# The seeded lab test IS at or near the max, so baseline should be the ID just before it
BASELINE_LAB_BEFORE_SEED=$((${NEW_LAB_ID:-0} - 1))
if [ "$BASELINE_LAB_BEFORE_SEED" -lt 0 ]; then BASELINE_LAB_BEFORE_SEED=0; fi

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"
echo "Seeded lab id: ${NEW_LAB_ID:-0} (agent must interact with this specific lab)"

echo "$BASELINE_LAB_BEFORE_SEED" > /tmp/hbac_baseline_lab_before_seed
echo "$BASELINE_DISEASE_MAX" > /tmp/hbac_baseline_disease_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/hbac_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/hbac_baseline_appt_max
for f in /tmp/hbac_baseline_* /tmp/hbac_seeded_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/hbac_task_start_date
chmod 666 /tmp/hbac_task_start_date 2>/dev/null || true

# --- 7. Ensure GNU Health is running ---
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5
take_screenshot /tmp/hbac_initial_state.png

echo "=== abnormal_hba1c_management setup complete ==="
echo "Target patient: Ana Isabel Betz (patient_id=$ANA_PATIENT_ID, PUID=GNU777ORG)"
echo "Seeded pending HbA1c lab test id: ${NEW_LAB_ID:-failed}"
echo "Tasks to complete:"
echo "  1. Find the pending HbA1c lab test for Ana Betz and enter result: 9.4%"
echo "  2. Validate/complete the lab test"
echo "  3. Add condition record for poor glycemic control (E10.x ICD-10 code)"
echo "  4. Prescribe insulin product for treatment intensification"
echo "  5. Schedule urgent follow-up in 7-28 days"
