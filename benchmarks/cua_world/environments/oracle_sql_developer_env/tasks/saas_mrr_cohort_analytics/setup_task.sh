#!/bin/bash
echo "=== Setting up SaaS MRR Cohort Analytics Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# Clean up previous run
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER saas_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# Create user
oracle_query "CREATE USER saas_admin IDENTIFIED BY SaaS2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO saas_admin;
GRANT RESOURCE TO saas_admin;
GRANT CREATE VIEW TO saas_admin;
GRANT CREATE TABLE TO saas_admin;
GRANT CREATE PROCEDURE TO saas_admin;
GRANT CREATE SESSION TO saas_admin;
EXIT;" "system"

echo "SAAS_ADMIN user created"

# Create schema and seed data
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON SERVEROUTPUT ON

CREATE TABLE plans (
    plan_id NUMBER PRIMARY KEY,
    plan_name VARCHAR2(50),
    mrr NUMBER
);

CREATE TABLE customers (
    customer_id NUMBER PRIMARY KEY,
    signup_date DATE
);

CREATE TABLE subscription_events (
    event_id NUMBER PRIMARY KEY,
    customer_id NUMBER REFERENCES customers(customer_id),
    event_date DATE,
    event_type VARCHAR2(50),
    old_mrr NUMBER,
    new_mrr NUMBER
);

CREATE SEQUENCE evt_seq START WITH 1 INCREMENT BY 1;

BEGIN
    -- Insert Plans
    INSERT INTO plans VALUES (0, 'Free', 0);
    INSERT INTO plans VALUES (1, 'Basic', 10);
    INSERT INTO plans VALUES (2, 'Pro', 50);
    INSERT INTO plans VALUES (3, 'Enterprise', 200);

    -- Generate normal customer baseline
    FOR i IN 1..100 LOOP
        INSERT INTO customers VALUES (i, DATE '2023-01-05' + MOD(i, 20));
        -- Initial signup
        INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, i, DATE '2023-01-05' + MOD(i, 20), 'START', 0, 50);
        
        -- Some churn
        IF MOD(i, 5) = 0 THEN
            INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, i, DATE '2023-04-10' + MOD(i, 10), 'CHURN', 50, 0);
        END IF;
    END LOOP;

    -- Generate Promo Abusers for MATCH_RECOGNIZE
    -- Abuser 1: 9991
    INSERT INTO customers VALUES (9991, DATE '2023-02-01');
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9991, DATE '2023-02-01', 'START', 0, 50);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9991, DATE '2023-02-10', 'CHURN', 50, 0); -- 9 days
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9991, DATE '2023-03-01', 'REACTIVATION', 0, 50);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9991, DATE '2023-03-12', 'CHURN', 50, 0); -- 11 days
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9991, DATE '2023-04-01', 'REACTIVATION', 0, 50);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9991, DATE '2023-04-10', 'CHURN', 50, 0); -- 9 days (3rd cycle)
    
    -- Abuser 2: 9992
    INSERT INTO customers VALUES (9992, DATE '2023-05-01');
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9992, DATE '2023-05-01', 'START', 0, 200);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9992, DATE '2023-05-14', 'CHURN', 200, 0); -- 13 days
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9992, DATE '2023-06-01', 'REACTIVATION', 0, 200);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9992, DATE '2023-06-10', 'CHURN', 200, 0); -- 9 days
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9992, DATE '2023-07-01', 'REACTIVATION', 0, 200);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9992, DATE '2023-07-12', 'CHURN', 200, 0); -- 11 days (3rd cycle)
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9992, DATE '2023-08-01', 'REACTIVATION', 0, 200);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9992, DATE '2023-08-05', 'CHURN', 200, 0); -- 4 days (4th cycle)

    -- Near miss (only 2 cycles)
    INSERT INTO customers VALUES (9993, DATE '2023-08-01');
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9993, DATE '2023-08-01', 'START', 0, 50);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9993, DATE '2023-08-10', 'CHURN', 50, 0); 
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9993, DATE '2023-09-01', 'REACTIVATION', 0, 50);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 9993, DATE '2023-09-10', 'CHURN', 50, 0);

    -- Specific Churn event for June 2023 to test Waterfall Categorization
    INSERT INTO customers VALUES (5001, DATE '2023-01-15');
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 5001, DATE '2023-01-15', 'START', 0, 50);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 5001, DATE '2023-06-15', 'CHURN', 50, 0);
    
    INSERT INTO customers VALUES (5002, DATE '2023-02-20');
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 5002, DATE '2023-02-20', 'START', 0, 200);
    INSERT INTO subscription_events VALUES (evt_seq.NEXTVAL, 5002, DATE '2023-06-20', 'CHURN', 200, 0);

    COMMIT;
END;
/
EXIT;
EOSQL

echo "Data seeding complete."

# Launch SQL Developer and Pre-configure Connection
ensure_hr_connection "SAAS Admin DB" "saas_admin" "SaaS2024"

# Wait for GUI and Focus
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Try to open connection automatically
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="