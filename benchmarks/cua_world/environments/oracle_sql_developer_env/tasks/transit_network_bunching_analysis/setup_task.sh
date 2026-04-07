#!/bin/bash
echo "=== Setting up Transit Network Bunching Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# 1. Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# 2. Clean up previous run artifacts
echo "Cleaning up previous schema..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
BEGIN
  EXECUTE IMMEDIATE 'DROP USER transit_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;
EOSQL

sleep 2

# 3. Create TRANSIT_ADMIN schema
echo "Creating TRANSIT_ADMIN schema..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE USER transit_admin IDENTIFIED BY Transit2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;

GRANT CONNECT, RESOURCE TO transit_admin;
GRANT CREATE VIEW, CREATE MATERIALIZED VIEW TO transit_admin;
GRANT CREATE PROCEDURE TO transit_admin;
GRANT CREATE SESSION TO transit_admin;
GRANT CREATE TABLE TO transit_admin;
EXIT;
EOSQL

# 4. Create Tables and Insert GTFS Sample Data
echo "Populating GTFS sample data..."
sudo docker exec -i oracle-xe sqlplus -s transit_admin/Transit2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE routes (
    route_id VARCHAR2(50) PRIMARY KEY,
    route_short_name VARCHAR2(10),
    route_long_name VARCHAR2(100),
    route_type NUMBER
);

CREATE TABLE trips (
    trip_id VARCHAR2(50) PRIMARY KEY,
    route_id VARCHAR2(50) REFERENCES routes(route_id),
    service_id VARCHAR2(50),
    direction_id NUMBER
);

CREATE TABLE stops (
    stop_id VARCHAR2(50) PRIMARY KEY,
    stop_name VARCHAR2(100),
    stop_lat NUMBER(10,6),
    stop_lon NUMBER(10,6)
);

CREATE TABLE stop_times (
    trip_id VARCHAR2(50) REFERENCES trips(trip_id),
    arrival_time VARCHAR2(20),
    departure_time VARCHAR2(20),
    stop_id VARCHAR2(50) REFERENCES stops(stop_id),
    stop_sequence NUMBER,
    PRIMARY KEY (trip_id, stop_sequence)
);

-- Insert Routes
INSERT INTO routes VALUES ('R1', '1', 'Metric/South Congress', 3);
INSERT INTO routes VALUES ('R801', '801', 'N Lamar/S Congress Rapid', 3);

-- Insert Stops
INSERT INTO stops VALUES ('S1', 'North Transit Center', 30.3, -97.7);
INSERT INTO stops VALUES ('S2', 'Central Station', 30.2, -97.7);
INSERT INTO stops VALUES ('S3', 'South Transit Center', 30.1, -97.7);

-- Insert Trips for Route 1 (Direction 0)
INSERT INTO trips VALUES ('T1-1', 'R1', 'WEEKDAY', 0);
INSERT INTO trips VALUES ('T1-2', 'R1', 'WEEKDAY', 0);
INSERT INTO trips VALUES ('T1-3', 'R1', 'WEEKDAY', 0);

-- Normal spacing (15 mins)
INSERT INTO stop_times VALUES ('T1-1', '08:00:00', '08:00:00', 'S1', 1);
INSERT INTO stop_times VALUES ('T1-1', '08:15:00', '08:16:00', 'S2', 2);
INSERT INTO stop_times VALUES ('T1-1', '08:30:00', '08:30:00', 'S3', 3);

INSERT INTO stop_times VALUES ('T1-2', '08:15:00', '08:15:00', 'S1', 1);
INSERT INTO stop_times VALUES ('T1-2', '08:30:00', '08:31:00', 'S2', 2);
INSERT INTO stop_times VALUES ('T1-2', '08:45:00', '08:45:00', 'S3', 3);

-- Bunched Trip! Scheduled 3 mins behind T1-2
INSERT INTO stop_times VALUES ('T1-3', '08:18:00', '08:18:00', 'S1', 1);
INSERT INTO stop_times VALUES ('T1-3', '08:33:00', '08:34:00', 'S2', 2);
INSERT INTO stop_times VALUES ('T1-3', '08:48:00', '08:48:00', 'S3', 3);

-- Insert Trips for Route 801 (Late Night / >24hr GTFS Quirk)
INSERT INTO trips VALUES ('T801-1', 'R801', 'WEEKDAY', 1);
INSERT INTO trips VALUES ('T801-2', 'R801', 'WEEKDAY', 1);

-- Late night trips
INSERT INTO stop_times VALUES ('T801-1', '24:45:00', '24:45:00', 'S1', 1);
INSERT INTO stop_times VALUES ('T801-1', '25:05:00', '25:06:00', 'S2', 2);

-- Bunched Late Night Trip! 4 mins behind
INSERT INTO stop_times VALUES ('T801-2', '24:49:00', '24:49:00', 'S1', 1);
INSERT INTO stop_times VALUES ('T801-2', '25:09:00', '25:10:00', 'S2', 2);

COMMIT;
EXIT;
EOSQL

echo "GTFS data loaded."

# 5. Connect SQL Developer properly
ensure_hr_connection "Transit Database" "transit_admin" "Transit2024"
open_hr_connection_in_sqldeveloper

# Take Initial Screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="