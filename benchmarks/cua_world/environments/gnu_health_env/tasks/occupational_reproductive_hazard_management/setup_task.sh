#!/bin/bash
echo "=== Setting up occupational_reproductive_hazard_management task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find patient Luna ---
LUNA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Luna%'
      AND (pp.lastname IS NULL OR TRIM(pp.lastname) = '' OR pp.lastname ILIKE '%Luna%')
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$LUNA_PATIENT_ID" ]; then
    LUNA_PATIENT_ID=$(gnuhealth_db_query "
        SELECT gp.id
        FROM gnuhealth_patient gp
        JOIN party_party pp ON gp.party = pp.id
        WHERE CONCAT(COALESCE(pp.name,''), ' ', COALESCE(pp.lastname,'')) ILIKE '%Luna%'
        LIMIT 1" | tr -d '[:space:]')
fi

if [ -z "$LUNA_PATIENT_ID" ]; then
    echo "FATAL: Patient 'Luna' not found in demo database. Aborting."
    exit 1
fi

LUNA_PARTY_ID=$(gnuhealth_db_query "SELECT party FROM gnuhealth_patient WHERE id = $LUNA_PATIENT_ID LIMIT 1" | tr -d '[:space:]')

echo "Luna patient_id: $LUNA_PATIENT_ID, party_id: $LUNA_PARTY_ID"
echo "$LUNA_PATIENT_ID" > /tmp/repro_target_patient_id
echo "$LUNA_PARTY_ID" > /tmp/repro_target_party_id
chmod 666 /tmp/repro_target_patient_id /tmp/repro_target_party_id 2>/dev/null || true

# --- 2. Ensure Maternity/Baseline Lab Types Exist ---
echo "Ensuring required lab test types exist..."
for lab_info in "HCG|HUMAN CHORIONIC GONADOTROPIN" "URINALYSIS|ROUTINE URINALYSIS" "CBC|COMPLETE BLOOD COUNT" "BLOOD_TYPING|BLOOD TYPING AND RH"; do
    code="${lab_info%|*}"
    name="${lab_info#*|}"
    gnuhealth_db_query "
        INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
        SELECT
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
            '$name', '$code', true, 1, NOW(), 1, NOW()
        WHERE NOT EXISTS (
            SELECT 1 FROM gnuhealth_lab_test_type WHERE code = '$code' OR UPPER(name) LIKE '%${name:0:10}%'
        );
    " 2>/dev/null || true
done

# --- 3. Contamination injection: Z33 Pregnancy on Ana Betz ---
echo "Injecting contamination: Pregnancy on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    Z33_PATHOLOGY_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code = 'Z33' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$Z33_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $Z33_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $Z33_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean any pre-existing records for Luna ---
echo "Cleaning pre-existing pregnancy, hazard, and lifestyle records for Luna..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $LUNA_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'O09%' OR code LIKE 'Z33%' OR code LIKE 'Z34%' OR code LIKE 'Z57%')
" 2>/dev/null || true

gnuhealth_db_query "DELETE FROM gnuhealth_patient_lifestyle WHERE patient_lifestyle = $LUNA_PATIENT_ID" 2>/dev/null || true
gnuhealth_db_query "DELETE FROM gnuhealth_patient_lifestyle WHERE patient = $LUNA_PATIENT_ID" 2>/dev/null || true

# --- 5. Record baselines for anti-gaming ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_PRESC_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_LIFESTYLE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lifestyle" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/repro_baseline_disease_max
echo "$BASELINE_PRESC_MAX" > /tmp/repro_baseline_presc_max
echo "$BASELINE_LAB_MAX" > /tmp/repro_baseline_lab_max
echo "$BASELINE_LIFESTYLE_MAX" > /tmp/repro_baseline_lifestyle_max
for f in /tmp/repro_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%s > /tmp/task_start_time
date +%Y-%m-%d > /tmp/repro_task_start_date
chmod 666 /tmp/task_start_time /tmp/repro_task_start_date 2>/dev/null || true

# --- 6. Start GUI / Browser ---
echo "Starting GNU Health Web Interface in Firefox..."
ensure_firefox_gnuhealth
sleep 2

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Clear any popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Final initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="