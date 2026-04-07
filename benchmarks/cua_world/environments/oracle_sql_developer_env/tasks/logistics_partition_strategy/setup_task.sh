#!/bin/bash
# Setup script for Logistics Partition Strategy task
echo "=== Setting up Logistics Partition Strategy ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# Clean up schema
echo "Cleaning up previous schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER logistics_mgr CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# Create schema
echo "Creating LOGISTICS_MGR schema..."
oracle_query "CREATE USER logistics_mgr IDENTIFIED BY Logistics2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE PROCEDURE TO logistics_mgr;
GRANT CREATE TABLE, CREATE SESSION TO logistics_mgr;
EXIT;" "system"

# Create base tables and generate massive data
echo "Creating tables and generating data (~550,000 rows)..."
sudo docker exec -i oracle-xe sqlplus -s logistics_mgr/Logistics2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE carriers (
    carrier_id NUMBER PRIMARY KEY,
    carrier_code VARCHAR2(10),
    carrier_name VARCHAR2(50),
    service_type VARCHAR2(30)
);

INSERT INTO carriers VALUES (1, 'FDX', 'FedEx', 'EXPRESS');
INSERT INTO carriers VALUES (2, 'UPS', 'UPS', 'GROUND');
INSERT INTO carriers VALUES (3, 'USPS', 'USPS', 'POSTAL');
INSERT INTO carriers VALUES (4, 'DHL', 'DHL', 'INTERNATIONAL');
INSERT INTO carriers VALUES (5, 'AMZN', 'Amazon Logistics', 'LAST_MILE');
INSERT INTO carriers VALUES (6, 'ONTR', 'OnTrac', 'REGIONAL');
INSERT INTO carriers VALUES (7, 'LSHIP', 'LaserShip', 'REGIONAL');
INSERT INTO carriers VALUES (8, 'XPO', 'XPO Logistics', 'FREIGHT');

CREATE TABLE regions (
    region_id NUMBER PRIMARY KEY,
    region_name VARCHAR2(20)
);

INSERT INTO regions VALUES (1, 'NORTHEAST');
INSERT INTO regions VALUES (2, 'SOUTHEAST');
INSERT INTO regions VALUES (3, 'MIDWEST');
INSERT INTO regions VALUES (4, 'SOUTHWEST');
INSERT INTO regions VALUES (5, 'WEST');

CREATE TABLE warehouses (
    warehouse_id NUMBER PRIMARY KEY,
    warehouse_name VARCHAR2(80),
    city VARCHAR2(60),
    state VARCHAR2(2),
    region_id NUMBER,
    zip_code VARCHAR2(10)
);

INSERT INTO warehouses 
SELECT rownum, 'Warehouse ' || rownum, 'City ' || rownum, 'ST', MOD(rownum, 5)+1, '1000' || MOD(rownum, 9)
FROM dual CONNECT BY level <= 20;

CREATE TABLE shipments (
    shipment_id NUMBER PRIMARY KEY,
    tracking_number VARCHAR2(30),
    carrier_id NUMBER,
    origin_warehouse_id NUMBER,
    dest_city VARCHAR2(60),
    dest_state VARCHAR2(2),
    dest_region VARCHAR2(20),
    dest_zip VARCHAR2(10),
    weight_lbs NUMBER(8,2),
    declared_value NUMBER(10,2),
    service_level VARCHAR2(20),
    created_date DATE,
    delivered_date DATE,
    status VARCHAR2(20)
);

CREATE TABLE shipment_events (
    event_id NUMBER PRIMARY KEY,
    shipment_id NUMBER,
    event_type VARCHAR2(30),
    event_date DATE,
    facility_name VARCHAR2(100),
    city VARCHAR2(60),
    state VARCHAR2(2),
    notes VARCHAR2(200)
);

COMMIT;

-- Generate 50k shipments
INSERT /*+ APPEND */ INTO shipments
SELECT rownum, 'TRK' || LPAD(rownum, 10, '0'),
       MOD(rownum, 8)+1, MOD(rownum, 20)+1, 'City_' || MOD(rownum, 100), 'ST',
       CASE MOD(rownum, 5) WHEN 0 THEN 'NORTHEAST' WHEN 1 THEN 'SOUTHEAST' WHEN 2 THEN 'MIDWEST' WHEN 3 THEN 'SOUTHWEST' ELSE 'WEST' END,
       '12345', ROUND(DBMS_RANDOM.VALUE(1,100),2), ROUND(DBMS_RANDOM.VALUE(10,1000),2),
       CASE MOD(rownum, 4) WHEN 0 THEN 'GROUND' WHEN 1 THEN 'EXPRESS' WHEN 2 THEN 'OVERNIGHT' ELSE 'FREIGHT' END,
       DATE '2023-01-01' + DBMS_RANDOM.VALUE(0, 729),
       DATE '2023-01-01' + DBMS_RANDOM.VALUE(0, 729) + DBMS_RANDOM.VALUE(1, 10),
       'DELIVERED'
FROM dual CONNECT BY level <= 50000;
COMMIT;

-- Generate 500k events
INSERT /*+ APPEND */ INTO shipment_events
SELECT rownum, MOD(rownum, 50000)+1,
       CASE MOD(rownum, 5) WHEN 0 THEN 'CREATED' WHEN 1 THEN 'PICKED_UP' WHEN 2 THEN 'IN_TRANSIT' WHEN 3 THEN 'OUT_FOR_DELIVERY' ELSE 'DELIVERED' END,
       DATE '2023-01-01' + DBMS_RANDOM.VALUE(0, 729),
       'Facility ' || MOD(rownum, 50), 'City_' || MOD(rownum, 100), 'ST', 'Status update'
FROM dual CONNECT BY level <= 500000;
COMMIT;

EXIT;
EOSQL
echo "Data generated successfully."

# Setup GUI
ensure_hr_connection "Logistics DB" "logistics_mgr" "Logistics2024"

# Clear old export plan
rm -f /home/ga/Documents/exports/partition_pruning_plan.txt

# Launch SQL Developer
if ! pgrep -f "sqldeveloper" > /dev/null; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper > /dev/null 2>&1 &"
    sleep 20
fi

# Try to open connection and focus
open_hr_connection_in_sqldeveloper "Logistics DB" || true

# Maximize Window
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup complete ==="