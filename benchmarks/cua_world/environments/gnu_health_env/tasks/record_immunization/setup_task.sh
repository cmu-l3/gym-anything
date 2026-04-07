#!/bin/bash
echo "=== Setting up record_immunization task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find patient Ana Betz to ensure she exists ---
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ANA_PATIENT_ID" ]; then
    echo "FATAL: Patient Ana Betz not found in demo database. Aborting."
    exit 1
fi
echo "Ana Betz patient_id: $ANA_PATIENT_ID"

# --- 2. Create the Hepatitis B Vaccine medicament if it doesn't exist ---
echo "Ensuring Hepatitis B Vaccine medicament exists..."
gnuhealth_db_query "
DO \$\$
DECLARE
    tmpl_id INTEGER;
    prod_id INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM product_template WHERE name = 'Hepatitis B Vaccine') THEN
        -- Insert product_template
        SELECT COALESCE(MAX(id),0)+1 INTO tmpl_id FROM product_template;
        INSERT INTO product_template (id, name, type, list_price, cost_price, default_uom, active, consumable, create_uid, create_date, write_uid, write_date)
        VALUES (tmpl_id, 'Hepatitis B Vaccine', 'goods', 0, 0, 1, true, true, 1, NOW(), 1, NOW());

        -- Insert product_product
        SELECT COALESCE(MAX(id),0)+1 INTO prod_id FROM product_product;
        INSERT INTO product_product (id, template, active, create_uid, create_date, write_uid, write_date)
        VALUES (prod_id, tmpl_id, true, 1, NOW(), 1, NOW());

        -- Insert gnuhealth_medicament
        INSERT INTO gnuhealth_medicament (id, name, is_vaccine, active, create_uid, create_date, write_uid, write_date)
        VALUES ((SELECT COALESCE(MAX(id),0)+1 FROM gnuhealth_medicament), prod_id, true, true, 1, NOW(), 1, NOW());
    END IF;
END \$\$;
" 2>/dev/null || true

# --- 3. Record baseline state (max vaccination ID) ---
BASELINE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_vaccination" | tr -d '[:space:]')
echo "Baseline vaccination max ID: $BASELINE_MAX"
echo "$BASELINE_MAX" > /tmp/baseline_vaccination_max
chmod 666 /tmp/baseline_vaccination_max 2>/dev/null || true

date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# --- 4. Ensure GNU Health is running & logged in ---
echo "Ensuring GNU Health is accessible..."
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="