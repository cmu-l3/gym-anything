#!/bin/bash
# Setup script for PL/SQL Bulk Processing Optimization task
# Creates necessary tables and populates them with 50,000 transactions
# Installs the inefficient row-by-row procedure

set -e

echo "=== Setting up PL/SQL Bulk Processing Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight Check ---
echo "[1/4] Checking Oracle status..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Create Tables and Data ---
echo "[2/4] Creating tables and generating 50,000 transactions..."

# Python script to generate SQL for massive data insertion (faster than pure SQL loops in setup)
python3 << 'PYEOF'
import random

# Generate SQL file
with open("/tmp/setup_data.sql", "w") as f:
    f.write("SET DEFINE OFF;\n")
    f.write("SET FEEDBACK OFF;\n")
    
    # Cleanup
    f.write("DROP TABLE settlement_log CASCADE CONSTRAINTS;\n")
    f.write("DROP TABLE daily_transactions CASCADE CONSTRAINTS;\n")
    f.write("DROP TABLE merchant_balances CASCADE CONSTRAINTS;\n")
    
    # Create Tables
    f.write("""
    CREATE TABLE merchant_balances (
        merchant_id NUMBER PRIMARY KEY,
        merchant_name VARCHAR2(100),
        balance NUMBER DEFAULT 0
    );
    
    CREATE TABLE daily_transactions (
        trans_id NUMBER PRIMARY KEY,
        merchant_id NUMBER,
        amount NUMBER,
        trans_date DATE DEFAULT SYSDATE,
        CONSTRAINT fk_dt_merch FOREIGN KEY (merchant_id) REFERENCES merchant_balances(merchant_id)
    );
    
    CREATE TABLE settlement_log (
        log_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        merchant_id NUMBER,
        amount_processed NUMBER,
        processed_at TIMESTAMP DEFAULT SYSTIMESTAMP
    );
    """)
    
    # Insert Merchants (1000)
    f.write("INSERT INTO merchant_balances (merchant_id, merchant_name, balance) SELECT level, 'Merchant ' || level, 0 FROM dual CONNECT BY level <= 1000;\n")
    f.write("COMMIT;\n")
    
    # Insert Transactions (50,000) using INSERT ALL for speed in blocks
    # Note: PL/SQL loop is cleaner for setup script than huge text file
    f.write("""
    BEGIN
        FOR i IN 1..50000 LOOP
            INSERT INTO daily_transactions (trans_id, merchant_id, amount, trans_date)
            VALUES (i, MOD(i, 1000) + 1, ROUND(DBMS_RANDOM.VALUE(10, 1000), 2), SYSDATE);
        END LOOP;
        COMMIT;
    END;
    /
    """)
PYEOF

# Execute the setup SQL
oracle_query "@ /tmp/setup_data.sql" "hr" > /dev/null

# --- Create the Slow Procedure ---
echo "[3/4] Installing inefficient legacy procedure..."
oracle_query "
CREATE OR REPLACE PROCEDURE PROCESS_DAILY_SETTLEMENTS IS
  CURSOR c_trans IS SELECT * FROM DAILY_TRANSACTIONS;
  v_rec DAILY_TRANSACTIONS%ROWTYPE;
BEGIN
  -- Row-by-row processing (The Anti-Pattern)
  OPEN c_trans;
  LOOP
    FETCH c_trans INTO v_rec;
    EXIT WHEN c_trans%NOTFOUND;
    
    -- Update balance
    UPDATE MERCHANT_BALANCES 
    SET balance = balance + v_rec.amount 
    WHERE merchant_id = v_rec.merchant_id;
    
    -- Log settlement
    INSERT INTO SETTLEMENT_LOG (merchant_id, amount_processed, processed_at)
    VALUES (v_rec.merchant_id, v_rec.amount, SYSTIMESTAMP);
    
    -- CRITICAL PERFORMANCE FLAW: Commit inside loop
    COMMIT;
    
  END LOOP;
  CLOSE c_trans;
END;
/" "hr"

# --- Record Initial State ---
echo "[4/4] Recording baseline..."
date +%s > /tmp/task_start_timestamp

# Store the total expected amount for verification
TOTAL_AMOUNT=$(oracle_query_raw "SELECT SUM(amount) FROM daily_transactions;" "hr" | tr -d ' ')
echo "$TOTAL_AMOUNT" > /tmp/expected_total_amount.txt
chmod 600 /tmp/expected_total_amount.txt

# Ensure DBeaver is ready (optional convenience)
if ! pgrep -f dbeaver > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /snap/bin/dbeaver-ce &" > /dev/null 2>&1 || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Procedure PROCESS_DAILY_SETTLEMENTS created."
echo "Data loaded: 1000 merchants, 50,000 transactions."