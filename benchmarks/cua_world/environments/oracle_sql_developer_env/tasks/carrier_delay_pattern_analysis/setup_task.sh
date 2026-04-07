#!/bin/bash
# Setup script for Carrier Delay Pattern Analysis task
echo "=== Setting up Carrier Delay Pattern Analysis ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# 1. Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# 2. Clean up previous run artifacts
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER logistics_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# 3. Create LOGISTICS schema with logistics_analyst user
echo "Creating LOGISTICS schema (logistics_analyst user)..."
oracle_query "CREATE USER logistics_analyst IDENTIFIED BY Logistics2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO logistics_analyst;
GRANT RESOURCE TO logistics_analyst;
GRANT CREATE VIEW TO logistics_analyst;
GRANT CREATE PROCEDURE TO logistics_analyst;
GRANT CREATE SESSION TO logistics_analyst;
GRANT CREATE TABLE TO logistics_analyst;
GRANT CREATE SEQUENCE TO logistics_analyst;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create logistics_analyst user"
    exit 1
fi

# 4. Create Tables and Insert Data
echo "Creating schema tables and injecting data..."

sudo docker exec -i oracle-xe sqlplus -s logistics_analyst/Logistics2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE carriers (
    carrier_id    NUMBER PRIMARY KEY,
    carrier_name  VARCHAR2(100),
    carrier_code  VARCHAR2(10),
    carrier_type  VARCHAR2(30)
);

CREATE TABLE routes (
    route_id      NUMBER PRIMARY KEY,
    origin_city   VARCHAR2(50),
    dest_city     VARCHAR2(50),
    distance_miles NUMBER,
    sla_hours     NUMBER
);

CREATE TABLE shipments (
    shipment_id       NUMBER PRIMARY KEY,
    carrier_id        NUMBER REFERENCES carriers(carrier_id),
    route_id          NUMBER REFERENCES routes(route_id),
    ship_date         DATE,
    expected_delivery DATE,
    actual_delivery   DATE,
    cost              NUMBER(10,2),
    status            VARCHAR2(20)
);

-- Insert Carriers
INSERT INTO carriers VALUES (101, 'Heartland Express', 'HTLD', 'FTL');
INSERT INTO carriers VALUES (102, 'FedEx Freight', 'FXF', 'LTL');
INSERT INTO carriers VALUES (103, 'JB Hunt', 'JBH', 'INTERMODAL');

-- Insert Routes
INSERT INTO routes VALUES (201, 'Chicago', 'Detroit', 280, 6);
INSERT INTO routes VALUES (202, 'Dallas', 'Houston', 240, 5);
INSERT INTO routes VALUES (203, 'Los Angeles', 'San Francisco', 380, 8);

-- Insert Shipments
-- Pattern 1: Heartland Express (101) on Chicago->Detroit (201) has 3 consecutive delays
INSERT INTO shipments VALUES (1001, 101, 201, TO_DATE('2024-06-01 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-01 14:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-01 16:00', 'YYYY-MM-DD HH24:MI'), 500.00, 'DELIVERED'); -- Late
INSERT INTO shipments VALUES (1002, 101, 201, TO_DATE('2024-06-02 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-02 14:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-02 17:00', 'YYYY-MM-DD HH24:MI'), 500.00, 'DELIVERED'); -- Late
INSERT INTO shipments VALUES (1003, 101, 201, TO_DATE('2024-06-03 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-03 14:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-03 18:00', 'YYYY-MM-DD HH24:MI'), 500.00, 'DELIVERED'); -- Late (3rd consecutive)
INSERT INTO shipments VALUES (1004, 101, 201, TO_DATE('2024-06-04 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-04 14:00', 'YYYY-MM-DD HH24:MI'), NULL, 500.00, 'IN_TRANSIT'); -- At risk (0% historical on-time)

-- Pattern 2: Dallas->Houston (202) has a bottleneck (Avg transit = 7.5h, SLA = 5h. 7.5 > 5 * 1.2)
INSERT INTO shipments VALUES (1005, 102, 202, TO_DATE('2024-06-01 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-01 13:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-01 16:00', 'YYYY-MM-DD HH24:MI'), 300.00, 'DELIVERED'); -- 8 hrs
INSERT INTO shipments VALUES (1006, 103, 202, TO_DATE('2024-06-02 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-02 13:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-02 15:00', 'YYYY-MM-DD HH24:MI'), 350.00, 'DELIVERED'); -- 7 hrs

-- Normal shipments
INSERT INTO shipments VALUES (1007, 103, 203, TO_DATE('2024-06-01 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-01 16:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-01 15:30', 'YYYY-MM-DD HH24:MI'), 800.00, 'DELIVERED'); -- On time
INSERT INTO shipments VALUES (1008, 103, 203, TO_DATE('2024-06-05 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-06-05 16:00', 'YYYY-MM-DD HH24:MI'), NULL, 800.00, 'IN_TRANSIT'); -- Healthy transit

COMMIT;
EXIT;
EOSQL
echo "Data injected."

# 5. Pre-configure SQL Developer Connection
echo "Pre-configuring SQL Developer connection..."
ensure_hr_connection "Logistics DB" "logistics_analyst" "Logistics2024"

# Remove any old CSV file to avoid false positives
rm -f /home/ga/carrier_performance.csv

# 6. Take initial screenshot
sleep 2
DISPLAY=:1 wmctrl -r "Oracle SQL Developer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="