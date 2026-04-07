#!/bin/bash
echo "=== Setting up occupational_cytotoxic_exposure task ==="

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
    echo "FATAL: Patient Ana Isabel Betz not found in demo database. Aborting."
    exit 1
fi
echo "Ana Isabel Betz patient_id: $ANA_PATIENT_ID"
echo "$ANA_PATIENT_ID" > /tmp/cyto_target_patient_id
chmod 666 /tmp/cyto_target_patient_id 2>/dev/null || true

# --- 2. Ensure lab test types exist ---
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

echo "Ensuring CMP lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPREHENSIVE METABOLIC PANEL', 'CMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CMP' OR UPPER(name) LIKE '%COMPREHENSIVE METABOLIC%'
    );
" 2>/dev/null || true

echo "Ensuring HEPATIC FUNCTION PANEL lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'HEPATIC FUNCTION PANEL', 'HEPATIC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'HEPATIC' OR UPPER(name) LIKE '%HEPATIC%' OR UPPER(name) LIKE '%LIVER%'
    );
" 2>/dev/null || true

# --- 3. Ensure Sodium Chloride/Saline medicament exists ---
echo "Ensuring Saline Solution medicament exists..."
gnuhealth_db_query "
    INSERT INTO product_template (id, name, type, list_price, cost_price, default_uom, active, consumable, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM product_template),
        'Sodium Chloride 0.9% (Saline Solution)', 'consumable', 5.0, 2.0, 1, true, true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM product_template WHERE LOWER(name) LIKE '%sodium chloride%' OR LOWER(name) LIKE '%saline solution%'
    );
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO product_product (id, template, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM product_product),
        (SELECT id FROM product_template WHERE LOWER(name) LIKE '%saline solution%' LIMIT 1),
        true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM product_product WHERE template IN (SELECT id FROM product_template WHERE LOWER(name) LIKE '%saline solution%')
    );
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_medicament (id, name, is_active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_medicament),
        (SELECT id FROM product_product WHERE template IN (SELECT id FROM product_template WHERE LOWER(name) LIKE '%saline solution%') LIMIT 1),
        true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_medicament WHERE name IN (
            SELECT id FROM product_product WHERE template IN (SELECT id FROM product_template WHERE LOWER(name) LIKE '%saline solution%')
        )
    );
" 2>/dev/null || true

# --- 4. Contamination: T45 exposure on Roberto Carlos (wrong patient) ---
echo "Injecting contamination: T45 on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    T45_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T45%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T45_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $T45_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $T45_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 5. Clean pre-existing T-code records and evaluations for Ana ---
echo "Cleaning pre-existing T-code disease records for Ana..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $ANA_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for Ana from today..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $ANA_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 6. Record baselines ---
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

echo "$BASELINE_DISEASE_MAX" > /tmp/cyto_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/cyto_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/cyto_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/cyto_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/cyto_baseline_appt_max
for f in /tmp/cyto_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/cyto_task_start_date
chmod 666 /tmp/cyto_task_start_date 2>/dev/null || true

# --- 7. Start Firefox ---
ensure_firefox_gnuhealth
sleep 2

echo "=== Setup complete ==="