#!/bin/bash
# Setup script for Aircraft Cascading Delay Analysis task
echo "=== Setting up Aircraft Cascading Delay Analysis ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# -------------------------------------------------------
# Verify Oracle container is running
# -------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# -------------------------------------------------------
# Clean up previous run artifacts
# -------------------------------------------------------
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER flight_ops CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" "OraclePassword123" 2>/dev/null || true
sleep 2

# -------------------------------------------------------
# Create FLIGHT_OPS user
# -------------------------------------------------------
echo "Creating FLIGHT_OPS user..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE USER flight_ops IDENTIFIED BY "Flights2024"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS;

GRANT CONNECT, RESOURCE TO flight_ops;
GRANT CREATE VIEW TO flight_ops;
GRANT CREATE SESSION TO flight_ops;
GRANT CREATE TABLE TO flight_ops;
EXIT;
EOSQL

# -------------------------------------------------------
# Create Tables & Seed Data
# -------------------------------------------------------
echo "Creating schemas and seeding data..."
sudo docker exec -i oracle-xe sqlplus -s flight_ops/Flights2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE airports (
    iata_code VARCHAR2(3) PRIMARY KEY,
    name VARCHAR2(100),
    city VARCHAR2(100),
    state VARCHAR2(2),
    latitude NUMBER(10,6),
    longitude NUMBER(10,6),
    is_hub NUMBER(1)
);

CREATE TABLE aircraft (
    tail_number VARCHAR2(10) PRIMARY KEY,
    airline_code VARCHAR2(3),
    manufacturer VARCHAR2(50),
    model VARCHAR2(50),
    year_built NUMBER(4)
);

CREATE TABLE flights (
    flight_id NUMBER PRIMARY KEY,
    flight_date DATE,
    airline_code VARCHAR2(3),
    tail_number VARCHAR2(10) REFERENCES aircraft(tail_number),
    flight_number VARCHAR2(10),
    origin VARCHAR2(3) REFERENCES airports(iata_code),
    dest VARCHAR2(3) REFERENCES airports(iata_code),
    crs_dep_time NUMBER,
    actual_dep_time NUMBER,
    dep_delay NUMBER,
    crs_arr_time NUMBER,
    actual_arr_time NUMBER,
    arr_delay NUMBER,
    cancelled NUMBER(1),
    distance NUMBER
);

-- Seed Airports
INSERT INTO airports VALUES ('ORD', 'O''Hare', 'Chicago', 'IL', 41.97, -87.90, 1);
INSERT INTO airports VALUES ('ATL', 'Hartsfield', 'Atlanta', 'GA', 33.64, -84.42, 1);
INSERT INTO airports VALUES ('JFK', 'Kennedy', 'New York', 'NY', 40.64, -73.77, 1);

-- Seed Snowball Aircraft (N999) - A sequence of strictly increasing delays ending > 90
INSERT INTO aircraft VALUES ('N999', 'AA', 'Boeing', '737', 2015);
INSERT INTO flights VALUES (1, DATE '2024-01-15', 'AA', 'N999', '1001', 'JFK', 'ORD', 800, 810, 10, 1000, 1015, 15, 0, 700);
INSERT INTO flights VALUES (2, DATE '2024-01-15', 'AA', 'N999', '1002', 'ORD', 'ATL', 1100, 1130, 30, 1300, 1340, 40, 0, 600);
INSERT INTO flights VALUES (3, DATE '2024-01-15', 'AA', 'N999', '1003', 'ATL', 'JFK', 1430, 1530, 60, 1630, 1740, 70, 0, 750);
INSERT INTO flights VALUES (4, DATE '2024-01-15', 'AA', 'N999', '1004', 'JFK', 'ORD', 1830, 2010, 100, 2030, 2220, 110, 0, 700);

-- Seed Delay Amplifiers (12 events at ORD to satisfy > 10 requirement)
BEGIN
  FOR i IN 100..111 LOOP
    INSERT INTO aircraft VALUES ('N'||i, 'UA', 'Airbus', 'A320', 2018);
    -- Flight A: Arrives ORD basically on time (arr_delay = 5 <= 15)
    INSERT INTO flights VALUES (1000+i, DATE '2024-01-15', 'UA', 'N'||i, '2001', 'ATL', 'ORD', 800, 800, 0, 1000, 1005, 5, 0, 600);
    -- Flight B: Departs ORD late (dep_delay = 45 > 15), injected 40 mins
    INSERT INTO flights VALUES (2000+i, DATE '2024-01-15', 'UA', 'N'||i, '2002', 'ORD', 'JFK', 1100, 1145, 45, 1300, 1350, 50, 0, 700);
  END LOOP;
END;
/
COMMIT;
EXIT;
EOSQL
echo "Schema and test data initialized."

# -------------------------------------------------------
# Setup SQL Developer Connection & Workspace
# -------------------------------------------------------
ensure_hr_connection "Flight Ops DB" "flight_ops" "Flights2024"
open_hr_connection_in_sqldeveloper 2>/dev/null || true

# Prepare export directory
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Wait for UI and take initial screenshot
sleep 3
take_screenshot /tmp/task_start_screenshot.png ga

echo "=== Task Setup Complete ==="