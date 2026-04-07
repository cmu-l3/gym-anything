#!/bin/bash
echo "=== Setting up Telecom CDR Billing Engine Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Wait for Oracle container
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# Clean up previous runs
echo "Cleaning up previous schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER billing CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# Create BILLING schema
echo "Creating BILLING schema..."
oracle_query "CREATE USER billing IDENTIFIED BY Billing2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO billing;
GRANT RESOURCE TO billing;
GRANT CREATE VIEW TO billing;
GRANT CREATE MATERIALIZED VIEW TO billing;
GRANT CREATE TABLE TO billing;
GRANT CREATE SESSION TO billing;
EXIT;" "system"

# Create tables and insert deterministic test data
echo "Creating tables and inserting data..."
sudo docker exec -i oracle-xe sqlplus -s billing/Billing2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- 1. CUSTOMER_PLANS
CREATE TABLE customer_plans (
    caller_num VARCHAR2(20) PRIMARY KEY,
    base_rate NUMBER(10,2) NOT NULL
);
INSERT INTO customer_plans VALUES ('12025550001', 0.10);
INSERT INTO customer_plans VALUES ('12025550002', 0.15);

-- 2. PREFIX_RATES
CREATE TABLE prefix_rates (
    prefix VARCHAR2(10) PRIMARY KEY,
    destination_name VARCHAR2(100) NOT NULL,
    surcharge NUMBER(10,2) NOT NULL
);
-- Overlapping prefixes to test Longest Prefix Match
INSERT INTO prefix_rates VALUES ('44', 'United Kingdom', 0.50);
INSERT INTO prefix_rates VALUES ('447', 'UK Mobile', 1.20);
INSERT INTO prefix_rates VALUES ('33', 'France', 0.60);
INSERT INTO prefix_rates VALUES ('1', 'US/Canada', 0.00);

-- 3. TIME_BANDS
CREATE TABLE time_bands (
    day_type VARCHAR2(10) NOT NULL CHECK (day_type IN ('WEEKDAY', 'WEEKEND')),
    start_hour NUMBER(2) NOT NULL,
    end_hour NUMBER(2) NOT NULL,
    multiplier NUMBER(10,2) NOT NULL
);
INSERT INTO time_bands VALUES ('WEEKDAY', 8, 17, 1.0);  -- Peak
INSERT INTO time_bands VALUES ('WEEKDAY', 18, 23, 0.5); -- Off-Peak evening
INSERT INTO time_bands VALUES ('WEEKDAY', 0, 7, 0.5);   -- Off-Peak morning
INSERT INTO time_bands VALUES ('WEEKEND', 0, 23, 0.25); -- Weekend flat

-- 4. UNRATED_CDRS
CREATE TABLE unrated_cdrs (
    cdr_id NUMBER PRIMARY KEY,
    caller_num VARCHAR2(20) REFERENCES customer_plans(caller_num),
    called_num VARCHAR2(20) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    duration_seconds NUMBER NOT NULL
);
-- CDR 1: UK Mobile (447), Weekday (Wed), Peak (10:30), 65s -> 2m. Cost: 2 * (0.10 + 1.20) * 1.0 = 2.60
INSERT INTO unrated_cdrs VALUES (1, '12025550001', '447911123456', TIMESTAMP '2024-05-15 10:30:00', 65);
-- CDR 2: UK Landline (44), Weekend (Sat), 14:00, 120s -> 2m. Cost: 2 * (0.10 + 0.50) * 0.25 = 0.30
INSERT INTO unrated_cdrs VALUES (2, '12025550001', '442071234567', TIMESTAMP '2024-05-18 14:00:00', 120);
-- CDR 3: France (33), Weekday (Tue), Off-Peak (20:15), 45s -> 1m. Cost: 1 * (0.15 + 0.60) * 0.5 = 0.375
INSERT INTO unrated_cdrs VALUES (3, '12025550002', '33123456789', TIMESTAMP '2024-05-14 20:15:00', 45);
-- CDR 4: Local (No match), Weekday (Wed), Peak (09:00), 10s -> 1m. Cost: 1 * (0.15 + 0) * 1.0 = 0.15
INSERT INTO unrated_cdrs VALUES (4, '12025550002', '9999999999', TIMESTAMP '2024-05-15 09:00:00', 10);

COMMIT;
EXIT;
EOSQL

echo "Data populated successfully."

# Prepare SQL Developer connection
echo "Pre-configuring SQL Developer connection..."
ensure_hr_connection "Billing DB" "billing" "Billing2024"

# Create exports directory
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Open SQL Developer to the right connection if running
open_hr_connection_in_sqldeveloper || true

# Maximize SQL Developer window if running
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="