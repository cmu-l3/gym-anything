#!/bin/bash
# Setup script for Credit Card Rewards FIFO Liability task
echo "=== Setting up Credit Card Rewards FIFO Liability Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# ---------------------------------------------------------------
# 1. Verify Oracle is running
# ---------------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# ---------------------------------------------------------------
# 2. Clean up previous run artifacts
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER rewards_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Create REWARDS_ADMIN schema
# ---------------------------------------------------------------
echo "Creating REWARDS_ADMIN schema..."

oracle_query "CREATE USER rewards_admin IDENTIFIED BY Rewards2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO rewards_admin;
GRANT RESOURCE TO rewards_admin;
GRANT CREATE VIEW TO rewards_admin;
GRANT CREATE MATERIALIZED VIEW TO rewards_admin;
GRANT CREATE PROCEDURE TO rewards_admin;
GRANT CREATE SESSION TO rewards_admin;
GRANT CREATE SEQUENCE TO rewards_admin;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create rewards_admin user"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Create Tables and Sequences
# ---------------------------------------------------------------
echo "Creating REWARDS tables..."

sudo docker exec -i oracle-xe sqlplus -s rewards_admin/Rewards2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE customers (
    cust_id       NUMBER PRIMARY KEY,
    join_date     DATE NOT NULL,
    tier_level    VARCHAR2(20) NOT NULL
);

CREATE TABLE earn_events (
    earn_id          NUMBER PRIMARY KEY,
    cust_id          NUMBER REFERENCES customers(cust_id),
    transaction_date DATE NOT NULL,
    points_amount    NUMBER NOT NULL,
    expire_date      DATE NOT NULL
);

CREATE TABLE redemption_events (
    redemption_id    NUMBER PRIMARY KEY,
    cust_id          NUMBER REFERENCES customers(cust_id),
    transaction_date DATE NOT NULL,
    points_redeemed  NUMBER NOT NULL
);

CREATE TABLE expired_points_log (
    log_id           NUMBER PRIMARY KEY,
    earn_id          NUMBER REFERENCES earn_events(earn_id),
    cust_id          NUMBER REFERENCES customers(cust_id),
    points_expired   NUMBER NOT NULL,
    expired_date     DATE NOT NULL
);

CREATE SEQUENCE expire_log_seq START WITH 1 INCREMENT BY 1 NOCACHE;

EXIT;
EOSQL

# ---------------------------------------------------------------
# 5. Generate Realistic Data via PL/SQL (Deterministic)
# ---------------------------------------------------------------
echo "Generating realistic transaction data (this takes ~10 seconds)..."

sudo docker exec -i oracle-xe sqlplus -s rewards_admin/Rewards2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET SERVEROUTPUT ON
DECLARE
    v_earn_id NUMBER := 1;
    v_redeem_id NUMBER := 1;
    v_join_date DATE;
    v_tier VARCHAR2(20);
    v_earn_date DATE;
    v_points NUMBER;
    v_total_earned NUMBER;
    v_redeemed NUMBER;
BEGIN
    -- Seed random generator for deterministic results across runs
    DBMS_RANDOM.SEED(42);

    FOR c IN 1..1000 LOOP
        -- Generate customer
        v_join_date := DATE '2020-01-01' + TRUNC(DBMS_RANDOM.VALUE(0, 730));
        
        IF DBMS_RANDOM.VALUE > 0.8 THEN
            v_tier := 'PLATINUM';
        ELSIF DBMS_RANDOM.VALUE > 0.5 THEN
            v_tier := 'GOLD';
        ELSE
            v_tier := 'SILVER';
        END IF;
        
        INSERT INTO customers VALUES (c, v_join_date, v_tier);
        
        -- Generate 12 to 36 earn events per customer
        v_total_earned := 0;
        FOR e IN 1..ROUND(DBMS_RANDOM.VALUE(12, 36)) LOOP
            v_earn_date := v_join_date + (e * 30) + TRUNC(DBMS_RANDOM.VALUE(-5, 5));
            -- Don't generate future earn events
            IF v_earn_date > DATE '2024-12-31' THEN
                EXIT;
            END IF;
            
            IF v_tier = 'PLATINUM' THEN v_points := ROUND(DBMS_RANDOM.VALUE(500, 2000));
            ELSIF v_tier = 'GOLD' THEN v_points := ROUND(DBMS_RANDOM.VALUE(200, 1000));
            ELSE v_points := ROUND(DBMS_RANDOM.VALUE(50, 500));
            END IF;
            
            v_total_earned := v_total_earned + v_points;
            
            -- Points expire 36 months after earning
            INSERT INTO earn_events VALUES (v_earn_id, c, v_earn_date, v_points, ADD_MONTHS(v_earn_date, 36));
            v_earn_id := v_earn_id + 1;
        END LOOP;
        
        -- Generate redemptions (consume roughly 40-90% of earned points)
        v_redeemed := 0;
        FOR r IN 1..ROUND(DBMS_RANDOM.VALUE(1, 5)) LOOP
            v_points := ROUND(DBMS_RANDOM.VALUE(v_total_earned * 0.1, v_total_earned * 0.3));
            IF v_redeemed + v_points < v_total_earned THEN
                INSERT INTO redemption_events VALUES (
                    v_redeem_id, 
                    c, 
                    v_join_date + 365 + TRUNC(DBMS_RANDOM.VALUE(0, 700)), 
                    v_points
                );
                v_redeem_id := v_redeem_id + 1;
                v_redeemed := v_redeemed + v_points;
            END IF;
        END LOOP;
    END LOOP;
    COMMIT;
END;
/
EXIT;
EOSQL

echo "Data generation complete."

# ---------------------------------------------------------------
# 6. Configure SQL Developer Connection
# ---------------------------------------------------------------
echo "Configuring SQL Developer connection..."
# Use the function from task_utils.sh to inject the connection configuration
ensure_hr_connection "Rewards Database" "rewards_admin" "Rewards2024"

# Force focus on SQL Developer if it's already running
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="