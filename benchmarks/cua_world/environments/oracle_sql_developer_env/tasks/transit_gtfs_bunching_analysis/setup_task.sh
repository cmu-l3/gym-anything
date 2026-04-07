#!/bin/bash
# Setup script for Transit GTFS Bunching Analysis task
echo "=== Setting up Transit GTFS Bunching Analysis Task ==="

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
  EXECUTE IMMEDIATE 'DROP USER transit_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Create TRANSIT_ADMIN schema
# ---------------------------------------------------------------
echo "Creating TRANSIT_ADMIN schema..."

oracle_query "CREATE USER transit_admin IDENTIFIED BY Transit2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO transit_admin;
GRANT RESOURCE TO transit_admin;
GRANT CREATE VIEW TO transit_admin;
GRANT CREATE MATERIALIZED VIEW TO transit_admin;
GRANT CREATE PROCEDURE TO transit_admin;
GRANT CREATE SESSION TO transit_admin;
GRANT CREATE TABLE TO transit_admin;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create transit_admin user"
    exit 1
fi
echo "transit_admin user created with required privileges"

# ---------------------------------------------------------------
# 4. Create Tables and Insert Data
# ---------------------------------------------------------------
echo "Creating GTFS tables and inserting data..."

sudo docker exec -i oracle-xe sqlplus -s transit_admin/Transit2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE routes (
    route_id         VARCHAR2(10) PRIMARY KEY,
    route_short_name VARCHAR2(50) NOT NULL,
    route_long_name  VARCHAR2(200) NOT NULL,
    route_type       NUMBER
);

CREATE TABLE trips (
    trip_id      VARCHAR2(20) PRIMARY KEY,
    route_id     VARCHAR2(10) REFERENCES routes(route_id),
    service_id   VARCHAR2(20),
    direction_id NUMBER
);

CREATE TABLE stops (
    stop_id   VARCHAR2(20) PRIMARY KEY,
    stop_code VARCHAR2(20),
    stop_name VARCHAR2(100),
    stop_lat  NUMBER(10,6),
    stop_lon  NUMBER(10,6)
);

CREATE TABLE stop_times (
    trip_id        VARCHAR2(20) REFERENCES trips(trip_id),
    arrival_time   VARCHAR2(8) NOT NULL,
    departure_time VARCHAR2(8) NOT NULL,
    stop_id        VARCHAR2(20) REFERENCES stops(stop_id),
    stop_sequence  NUMBER,
    PRIMARY KEY (trip_id, stop_sequence)
);

CREATE TABLE vehicle_telemetry (
    telemetry_id        NUMBER PRIMARY KEY,
    trip_id             VARCHAR2(20) REFERENCES trips(trip_id),
    route_id            VARCHAR2(10) REFERENCES routes(route_id),
    direction_id        NUMBER,
    stop_id             VARCHAR2(20) REFERENCES stops(stop_id),
    vehicle_id          VARCHAR2(20),
    actual_arrival_time VARCHAR2(8)
);

-- Insert Routes
INSERT INTO routes VALUES ('R10', '10', 'Downtown Express', 3);
INSERT INTO routes VALUES ('R20', '20', 'Crosstown Local', 3);
INSERT INTO routes VALUES ('R30', '30', 'Airport Flyer', 3);

-- Insert Trips
INSERT INTO trips VALUES ('T10_1', 'R10', 'WKDY', 0);
INSERT INTO trips VALUES ('T10_2', 'R10', 'WKDY', 0);
INSERT INTO trips VALUES ('T10_3', 'R10', 'WKDY', 0);
INSERT INTO trips VALUES ('T20_1', 'R20', 'WKDY', 1);

-- Insert Stops
INSERT INTO stops VALUES ('S100', '100', 'Central Station', 40.7128, -74.0060);
INSERT INTO stops VALUES ('S101', '101', 'City Hall', 40.7129, -74.0065);
INSERT INTO stops VALUES ('S102', '102', 'Financial District', 40.7110, -74.0090);

-- Insert Stop Times (GTFS format, some past midnight)
INSERT INTO stop_times VALUES ('T10_1', '24:30:00', '24:30:30', 'S100', 1);
INSERT INTO stop_times VALUES ('T10_1', '24:45:00', '24:45:30', 'S101', 2);
INSERT INTO stop_times VALUES ('T10_1', '25:00:00', '25:00:30', 'S102', 3);

INSERT INTO stop_times VALUES ('T10_2', '24:45:00', '24:45:30', 'S100', 1);
INSERT INTO stop_times VALUES ('T10_2', '25:00:00', '25:00:30', 'S101', 2);
INSERT INTO stop_times VALUES ('T10_2', '25:15:00', '25:15:30', 'S102', 3);

INSERT INTO stop_times VALUES ('T10_3', '25:00:00', '25:00:30', 'S100', 1);
INSERT INTO stop_times VALUES ('T10_3', '25:15:00', '25:15:30', 'S101', 2);
INSERT INTO stop_times VALUES ('T10_3', '25:30:00', '25:30:30', 'S102', 3);

INSERT INTO stop_times VALUES ('T20_1', '14:00:00', '14:00:30', 'S100', 1);

-- Insert Telemetry (Seed bunching events)
-- T10_1 is delayed by 30 mins
INSERT INTO vehicle_telemetry VALUES (1, 'T10_1', 'R10', 0, 'S100', 'BUS-A1', '25:00:00');
INSERT INTO vehicle_telemetry VALUES (2, 'T10_1', 'R10', 0, 'S101', 'BUS-A1', '25:15:00');
INSERT INTO vehicle_telemetry VALUES (3, 'T10_1', 'R10', 0, 'S102', 'BUS-A1', '25:30:00');

-- T10_2 is on time, so it bunches with T10_1 at S101 and S102 (arriving at 25:16:00, 1 min apart)
INSERT INTO vehicle_telemetry VALUES (4, 'T10_2', 'R10', 0, 'S100', 'BUS-A2', '24:45:00');
INSERT INTO vehicle_telemetry VALUES (5, 'T10_2', 'R10', 0, 'S101', 'BUS-A2', '25:16:00'); 
INSERT INTO vehicle_telemetry VALUES (6, 'T10_2', 'R10', 0, 'S102', 'BUS-A2', '25:32:00');

-- T10_3 is slightly early, bunches with T10_2 at S102 (arrives 25:33:00, 1 min apart from T10_2)
INSERT INTO vehicle_telemetry VALUES (7, 'T10_3', 'R10', 0, 'S100', 'BUS-A3', '25:00:00');
INSERT INTO vehicle_telemetry VALUES (8, 'T10_3', 'R10', 0, 'S101', 'BUS-A3', '25:15:00');
INSERT INTO vehicle_telemetry VALUES (9, 'T10_3', 'R10', 0, 'S102', 'BUS-A3', '25:33:00');

-- T20_1 on time
INSERT INTO vehicle_telemetry VALUES (10, 'T20_1', 'R20', 1, 'S100', 'BUS-B1', '14:02:00');

COMMIT;
EXIT;
EOSQL

echo "Data loaded successfully."

# ---------------------------------------------------------------
# 5. Prep Desktop Environment
# ---------------------------------------------------------------
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Setup Oracle SQL Developer connection
ensure_hr_connection "Transit Database" "transit_admin" "Transit2024"

# Launch Oracle SQL Developer in the background
echo "Launching Oracle SQL Developer..."
su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper > /tmp/sqldeveloper_launch.log 2>&1 &"

# Wait for window and maximize
sleep 20
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "SQL Developer window found and maximized."
        break
    fi
    sleep 2
done

# Try to open the connection directly via GUI macro if possible
open_hr_connection_in_sqldeveloper || echo "Could not auto-open connection, agent must click it."

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png ga

echo "=== Task Setup Complete ==="