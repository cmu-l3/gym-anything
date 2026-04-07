#!/bin/bash
# Setup for bulk_migration_save_exceptions task
# Creates source/target tables and populates source with ~50k rows (including ~1k invalid ones)

set -e

echo "=== Setting up Bulk Migration Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/5] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Clean up prior artifacts ---
echo "[2/5] Cleaning up schema..."
oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE stage_sales_legacy PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE fact_sales_prod PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE migration_errors PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE migrate_sales_bulk';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

# --- Create Tables ---
echo "[3/5] Creating tables..."
oracle_query "
-- Source Staging Table
CREATE TABLE stage_sales_legacy (
    sale_id     NUMBER PRIMARY KEY,
    sale_date   DATE,
    amount      NUMBER(10, 2),
    region      VARCHAR2(20),
    product_id  NUMBER
);

-- Target Production Table (with Constraint)
CREATE TABLE fact_sales_prod (
    sale_id     NUMBER PRIMARY KEY,
    sale_date   DATE,
    amount      NUMBER(10, 2),
    region      VARCHAR2(20),
    product_id  NUMBER,
    CONSTRAINT chk_sales_amount CHECK (amount >= 0)
);

-- Error Logging Table
CREATE TABLE migration_errors (
    error_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id       NUMBER,
    error_message VARCHAR2(4000),
    log_date      DATE DEFAULT SYSDATE
);
" "hr" > /dev/null 2>&1

# --- Generate Data ---
echo "[4/5] Generating 50,000 records (approx 2% invalid)..."

# We use a PL/SQL block to generate data fast
# ~50,000 rows total
# Modulo math to inject negative amounts occasionally
oracle_query "
DECLARE
    TYPE t_sales IS TABLE OF stage_sales_legacy%ROWTYPE;
    v_sales t_sales := t_sales();
    v_total_rows CONSTANT NUMBER := 50000;
    v_bad_count  NUMBER := 0;
BEGIN
    v_sales.EXTEND(v_total_rows);
    
    FOR i IN 1..v_total_rows LOOP
        v_sales(i).sale_id := i;
        v_sales(i).sale_date := DATE '2023-01-01' + MOD(i, 365);
        v_sales(i).region := CASE MOD(i, 4) 
                                WHEN 0 THEN 'North' 
                                WHEN 1 THEN 'South' 
                                WHEN 2 THEN 'East' 
                                ELSE 'West' 
                             END;
        v_sales(i).product_id := MOD(i, 100) + 1;
        
        -- Inject bad data (negative amount) every 47th record (arbitrary primeish number)
        IF MOD(i, 47) = 0 THEN
            v_sales(i).amount := -1 * ROUND(DBMS_RANDOM.VALUE(10, 500), 2);
            v_bad_count := v_bad_count + 1;
        ELSE
            v_sales(i).amount := ROUND(DBMS_RANDOM.VALUE(10, 500), 2);
        END IF;
    END LOOP;
    
    -- Bulk insert into staging
    FORALL i IN 1..v_total_rows
        INSERT INTO stage_sales_legacy VALUES v_sales(i);
        
    COMMIT;
    
    -- Store counts in a temp table for the export script to read easily later
    -- (We'll drop this later or just leave it as hidden metadata)
    EXECUTE IMMEDIATE 'CREATE TABLE task_metadata_hidden (key_name VARCHAR2(50), value_num NUMBER)';
    EXECUTE IMMEDIATE 'INSERT INTO task_metadata_hidden VALUES (''TOTAL_ROWS'', ' || v_total_rows || ')';
    EXECUTE IMMEDIATE 'INSERT INTO task_metadata_hidden VALUES (''BAD_ROWS'', ' || v_bad_count || ')';
    COMMIT;
END;
/" "hr"

# --- Create Reference File ---
echo "[5/5] Creating fragile example script..."
cat > /home/ga/Desktop/fragile_migration_example.sql << 'EOF'
-- This is a BAD example. It processes row-by-row and fails on the first error.
-- Do NOT use this approach. Use BULK COLLECT and SAVE EXCEPTIONS instead.

SET SERVEROUTPUT ON;
DECLARE
    CURSOR c_sales IS SELECT * FROM stage_sales_legacy;
BEGIN
    FOR r_sale IN c_sales LOOP
        -- This will crash the whole block if amount is negative
        INSERT INTO fact_sales_prod (sale_id, sale_date, amount, region, product_id)
        VALUES (r_sale.sale_id, r_sale.sale_date, r_sale.amount, r_sale.region, r_sale.product_id);
    END LOOP;
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Migration failed: ' || SQLERRM);
        ROLLBACK;
END;
/
EOF
chmod 644 /home/ga/Desktop/fragile_migration_example.sql

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="