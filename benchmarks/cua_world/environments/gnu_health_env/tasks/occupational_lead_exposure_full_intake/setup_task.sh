#!/bin/bash
echo "=== Setting up occupational_lead_exposure_full_intake task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

PREFIX="occl"

# ────────────────────────────────────────────────────────
# 1. FIX RATE LIMITING (root cause of all prior agent failures)
# ────────────────────────────────────────────────────────
echo "Clearing login attempt history to prevent rate-limiting..."
gnuhealth_db_query "DELETE FROM res_user_login_attempt;" 2>/dev/null || true

# ────────────────────────────────────────────────────────
# 2. ENSURE REQUIRED ICD-10 CODES EXIST
# ────────────────────────────────────────────────────────
echo "Ensuring ICD-10 pathology codes exist..."
declare -A ICD_NAMES
ICD_NAMES["T56.0"]="Toxic effect of lead and its compounds"
ICD_NAMES["D64.9"]="Anaemia, unspecified"
ICD_NAMES["I10"]="Essential (primary) hypertension"
ICD_NAMES["I25.1"]="Atherosclerotic heart disease"
ICD_NAMES["E11"]="Type 2 diabetes mellitus"

for CODE in "T56.0" "D64.9" "I10" "I25.1" "E11"; do
    NAME="${ICD_NAMES[$CODE]}"
    gnuhealth_db_query "
        INSERT INTO gnuhealth_pathology (id, code, name, active, create_uid, create_date, write_uid, write_date)
        SELECT COALESCE(MAX(id),0)+1, '$CODE', '$NAME', true, 1, NOW(), 1, NOW()
        FROM gnuhealth_pathology
        WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_pathology WHERE code='$CODE');
    " 2>/dev/null || true
done

# ────────────────────────────────────────────────────────
# 3. ENSURE REQUIRED LAB TEST TYPES EXIST (CBC, CMP)
# ────────────────────────────────────────────────────────
echo "Ensuring CBC and CMP lab test types exist..."

# Get a valid UOM for creating service products (needed by lab test types)
UOM_ID=$(gnuhealth_db_query "SELECT id FROM product_uom WHERE name='Unit' LIMIT 1" | tr -d '[:space:]')
if [ -z "$UOM_ID" ]; then
    UOM_ID=$(gnuhealth_db_query "SELECT id FROM product_uom LIMIT 1" | tr -d '[:space:]')
fi

insert_lab_test_type() {
    local CODE="$1"
    local NAME="$2"

    EXISTS=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_lab_test_type WHERE code='$CODE';" | tr -d '[:space:]')
    if [ "${EXISTS:-0}" -eq 0 ]; then
        echo "  Creating lab test type: $CODE ($NAME)"
        # Lab test types require a product_id (NOT NULL). Create a service product first.
        gnuhealth_db_query "
            INSERT INTO product_template (id, name, type, default_uom, create_uid, create_date, write_uid, write_date)
            VALUES (
                (SELECT COALESCE(MAX(id),0)+1 FROM product_template),
                '$NAME service', 'service', $UOM_ID, 1, NOW(), 1, NOW()
            );
        " 2>/dev/null || true
        TMPL_ID=$(gnuhealth_db_query "SELECT id FROM product_template WHERE name='$NAME service' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

        if [ -n "$TMPL_ID" ]; then
            gnuhealth_db_query "
                INSERT INTO product_product (id, template, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id),0)+1 FROM product_product),
                    $TMPL_ID, 1, NOW(), 1, NOW()
                );
            " 2>/dev/null || true
            PROD_ID=$(gnuhealth_db_query "SELECT id FROM product_product WHERE template=$TMPL_ID ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

            if [ -n "$PROD_ID" ]; then
                gnuhealth_db_query "
                    INSERT INTO gnuhealth_lab_test_type (id, code, name, product_id, active, create_uid, create_date, write_uid, write_date)
                    VALUES (
                        (SELECT COALESCE(MAX(id),0)+1 FROM gnuhealth_lab_test_type),
                        '$CODE', '$NAME', $PROD_ID, true, 1, NOW(), 1, NOW()
                    );
                " 2>/dev/null || true
            fi
        fi
    else
        echo "  Lab test type '$CODE' already exists."
    fi
}

insert_lab_test_type "CBC" "COMPLETE BLOOD COUNT"
insert_lab_test_type "CMP" "COMPREHENSIVE METABOLIC PANEL"

# ────────────────────────────────────────────────────────
# 4. ENSURE REQUIRED MEDICATIONS EXIST (Succimer, Ferrous Sulfate)
# ────────────────────────────────────────────────────────
echo "Ensuring medications exist in database..."

insert_medication() {
    local DRUG_NAME="$1"
    local SEARCH_PATTERN="$2"

    EXISTING=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM product_template
        WHERE UPPER(name) LIKE UPPER('%${SEARCH_PATTERN}%')
    " | tr -d '[:space:]')

    if [ "${EXISTING:-0}" -eq 0 ]; then
        echo "  Inserting medication: $DRUG_NAME"
        gnuhealth_db_query "
            INSERT INTO product_template (id, name, type, default_uom, create_uid, create_date, write_uid, write_date)
            VALUES (
                (SELECT COALESCE(MAX(id),0)+1 FROM product_template),
                '$DRUG_NAME', 'goods', $UOM_ID, 1, NOW(), 1, NOW()
            );
        " 2>/dev/null || true

        TMPL_ID=$(gnuhealth_db_query "SELECT id FROM product_template WHERE name='$DRUG_NAME' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
        if [ -n "$TMPL_ID" ]; then
            gnuhealth_db_query "
                INSERT INTO product_product (id, template, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id),0)+1 FROM product_product),
                    $TMPL_ID, 1, NOW(), 1, NOW()
                );
            " 2>/dev/null || true

            PROD_ID=$(gnuhealth_db_query "SELECT id FROM product_product WHERE template=$TMPL_ID ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
            if [ -n "$PROD_ID" ]; then
                gnuhealth_db_query "
                    INSERT INTO gnuhealth_medicament (id, product, create_uid, create_date, write_uid, write_date)
                    VALUES (
                        (SELECT COALESCE(MAX(id),0)+1 FROM gnuhealth_medicament),
                        $PROD_ID, 1, NOW(), 1, NOW()
                    );
                " 2>/dev/null || true
            fi
        fi
    else
        echo "  Medication '$DRUG_NAME' already exists."
    fi
}

insert_medication "Succimer (DMSA)" "succimer"
insert_medication "Ferrous Sulfate" "ferrous sulfate"

# ────────────────────────────────────────────────────────
# 5. CLEAN CONFLICTING STATE FROM PRIOR RUNS
# ────────────────────────────────────────────────────────
echo "Cleaning up prior run state..."

# Remove any pre-existing BLL_PANEL lab test type and its analytes
BLL_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_lab_test_type WHERE code='BLL_PANEL' LIMIT 1" | tr -d '[:space:]')
if [ -n "$BLL_ID" ]; then
    gnuhealth_db_query "DELETE FROM gnuhealth_patient_lab_test WHERE test_type = $BLL_ID" 2>/dev/null || true
    gnuhealth_db_query "DELETE FROM gnuhealth_lab_test_critearea WHERE test_type_id = $BLL_ID" 2>/dev/null || true
    gnuhealth_db_query "DELETE FROM gnuhealth_lab_test_type WHERE id = $BLL_ID" 2>/dev/null || true
fi

# Remove any prior Marcus Torres records (cascade through related tables)
MARCUS_PARTY_ID=$(gnuhealth_db_query "
    SELECT id FROM party_party
    WHERE name ILIKE '%Marcus%' AND lastname ILIKE '%Torres%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$MARCUS_PARTY_ID" ]; then
    MARCUS_PATIENT_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_patient WHERE party = $MARCUS_PARTY_ID LIMIT 1" | tr -d '[:space:]')

    if [ -n "$MARCUS_PATIENT_ID" ]; then
        # Delete in dependency order
        gnuhealth_db_query "DELETE FROM gnuhealth_prescription_line WHERE presc_order IN (SELECT id FROM gnuhealth_prescription_order WHERE patient = $MARCUS_PATIENT_ID)" 2>/dev/null || true
        gnuhealth_db_query "DELETE FROM gnuhealth_prescription_order WHERE patient = $MARCUS_PATIENT_ID" 2>/dev/null || true
        gnuhealth_db_query "DELETE FROM gnuhealth_patient_lab_test WHERE patient_id = $MARCUS_PATIENT_ID" 2>/dev/null || true
        gnuhealth_db_query "DELETE FROM gnuhealth_patient_evaluation WHERE patient = $MARCUS_PATIENT_ID" 2>/dev/null || true
        gnuhealth_db_query "DELETE FROM gnuhealth_patient_disease WHERE patient = $MARCUS_PATIENT_ID" 2>/dev/null || true
        gnuhealth_db_query "DELETE FROM gnuhealth_appointment WHERE patient = $MARCUS_PATIENT_ID" 2>/dev/null || true

        # Dynamically resolve family disease table name (varies across Tryton versions)
        FAMILY_TABLE=$(gnuhealth_db_query "
            SELECT table_name FROM information_schema.tables
            WHERE table_name IN ('gnuhealth_family_disease', 'gnuhealth_patient_family_diseases', 'gnuhealth_patient_family_disease')
            LIMIT 1" | tr -d '[:space:]')
        if [ -n "$FAMILY_TABLE" ]; then
            gnuhealth_db_query "DELETE FROM $FAMILY_TABLE WHERE patient = $MARCUS_PATIENT_ID" 2>/dev/null || true
        fi

        gnuhealth_db_query "DELETE FROM gnuhealth_patient WHERE id = $MARCUS_PATIENT_ID" 2>/dev/null || true
    fi

    gnuhealth_db_query "DELETE FROM party_party WHERE id = $MARCUS_PARTY_ID" 2>/dev/null || true
fi

# ────────────────────────────────────────────────────────
# 6. INJECT CONTAMINATION (anti-cheat decoys)
# ────────────────────────────────────────────────────────
echo "Injecting contamination records..."

# Add T56.0 diagnosis on Ana Betz (wrong patient) — trap for agents modifying wrong patient
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    T56_PATH_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code='T56.0' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T56_PATH_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $T56_PATH_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id),0)+1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $T56_PATH_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# ────────────────────────────────────────────────────────
# 7. RECORD BASELINES (AFTER cleanup, BEFORE agent acts)
# ────────────────────────────────────────────────────────
echo "Recording baseline state..."

# Resolve family disease table once and persist it
FAMILY_TABLE=$(gnuhealth_db_query "
    SELECT table_name FROM information_schema.tables
    WHERE table_name IN ('gnuhealth_family_disease', 'gnuhealth_patient_family_diseases', 'gnuhealth_patient_family_disease')
    LIMIT 1" | tr -d '[:space:]')
FAMILY_TABLE="${FAMILY_TABLE:-gnuhealth_family_disease}"
echo "$FAMILY_TABLE" > /tmp/${PREFIX}_family_table
chmod 666 /tmp/${PREFIX}_family_table 2>/dev/null || true

for TABLE in gnuhealth_lab_test_type gnuhealth_lab_test_critearea \
    gnuhealth_patient gnuhealth_patient_disease gnuhealth_patient_evaluation \
    gnuhealth_patient_lab_test \
    gnuhealth_prescription_order gnuhealth_appointment \
    party_party "$FAMILY_TABLE"; do
    MAX_ID=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM $TABLE" | tr -d '[:space:]')
    echo "$MAX_ID" > /tmp/${PREFIX}_baseline_${TABLE}_max
done

for f in /tmp/${PREFIX}_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/${PREFIX}_task_start_date
chmod 666 /tmp/${PREFIX}_task_start_date 2>/dev/null || true
date +%s > /tmp/${PREFIX}_task_start_time
chmod 666 /tmp/${PREFIX}_task_start_time 2>/dev/null || true

# ────────────────────────────────────────────────────────
# 8. LAUNCH AND LOGIN
# ────────────────────────────────────────────────────────
echo "Logging in to GNU Health..."
gnuhealth_db_query "DELETE FROM res_user_login_attempt;" 2>/dev/null || true
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"

take_screenshot /tmp/${PREFIX}_initial_state.png

echo "=== Task setup complete ==="
