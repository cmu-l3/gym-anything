#!/bin/bash
# Setup script for Autonomous Transaction Logging task
# Creates bank tables, loads initial data, and provides the flawed legacy code.

set -e

echo "=== Setting up Autonomous Transaction Logging Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container ($ORACLE_CONTAINER) not running!"
    exit 1
fi

# --- Pre-flight: Verify HR schema connectivity ---
echo "[2/4] Verifying HR schema connectivity..."
for attempt in {1..5}; do
    CONN_TEST=$(oracle_query_raw "SELECT 1 FROM DUAL;" "hr" 2>/dev/null | tr -d ' ')
    if [ "$CONN_TEST" == "1" ]; then
        echo "  Database ready."
        break
    fi
    echo "  Attempt $attempt failed, waiting 5s..."
    sleep 5
done

# --- Setup Database Objects ---
echo "[3/4] Creating database objects and legacy code..."

# Create a SQL script to set up the environment
cat > /tmp/setup_db.sql << 'SQLEOF'
-- Drop existing objects to ensure clean state
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE bank_accounts CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE system_logs CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE process_transfer';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE secure_log';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Create tables
CREATE TABLE bank_accounts (
    account_id NUMBER PRIMARY KEY,
    owner_name VARCHAR2(100),
    balance NUMBER(10,2) CHECK (balance >= 0)
);

CREATE TABLE system_logs (
    log_id NUMBER GENERATED ALWAYS AS IDENTITY,
    log_time TIMESTAMP DEFAULT SYSTIMESTAMP,
    severity VARCHAR2(20),
    message VARCHAR2(4000)
);

-- Insert initial data
INSERT INTO bank_accounts VALUES (1001, 'John Doe', 1000.00);
INSERT INTO bank_accounts VALUES (1002, 'Jane Smith', 2500.50);
COMMIT;

-- Create the flawed legacy procedure
CREATE OR REPLACE PROCEDURE PROCESS_TRANSFER(
    p_from IN NUMBER, p_to IN NUMBER, p_amount IN NUMBER
) IS
    v_balance NUMBER;
BEGIN
    -- Log start attempt (This will be lost on rollback in current implementation)
    INSERT INTO system_logs (severity, message) VALUES ('INFO', 'Transfer started: ' || p_amount || ' from ' || p_from);
    
    -- Deduct from sender
    UPDATE bank_accounts SET balance = balance - p_amount WHERE account_id = p_from;
    
    -- Add to receiver
    UPDATE bank_accounts SET balance = balance + p_amount WHERE account_id = p_to;
    
    -- Check balance (Simulating complex business logic check)
    SELECT balance INTO v_balance FROM bank_accounts WHERE account_id = p_from;
    
    IF v_balance < 0 THEN
        -- Log error (This will ALSO be lost on rollback!)
        INSERT INTO system_logs (severity, message) VALUES ('ERROR', 'Insufficient funds for account ' || p_from);
        RAISE_APPLICATION_ERROR(-20001, 'Insufficient funds: Balance cannot be negative');
    END IF;
    
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    -- The flaw: This ROLLBACK undoes the log inserts above
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Transaction failed: ' || SQLERRM);
    -- We re-raise to alert the caller, but the logs are gone
    RAISE;
END;
/
SQLEOF

# Execute the setup script
oracle_query "$(cat /tmp/setup_db.sql)" "hr" > /dev/null

# Provide the legacy code file for the agent to analyze
cp /tmp/setup_db.sql /home/ga/Desktop/legacy_payment_code.sql
# Clean up the setup commands from the user-facing file, keeping only the table/proc definitions
sed -i '1,20d' /home/ga/Desktop/legacy_payment_code.sql

# --- Record Timestamp ---
echo "[4/4] Recording task start time..."
date +%s > /tmp/task_start_time.txt
chmod 644 /tmp/task_start_time.txt

# Create a clean DBeaver shortcut or ensure it's in the menu
# (Assuming env handles this, but good to ensure terminal is ready)

echo "=== Setup Complete ==="