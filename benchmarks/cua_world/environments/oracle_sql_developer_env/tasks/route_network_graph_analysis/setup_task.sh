#!/bin/bash
# Setup script for Route Network Graph Analysis task
echo "=== Setting up Route Network Graph Analysis ==="

source /workspace/scripts/task_utils.sh

date +%s > /home/ga/.task_start_time

# 1. Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# 2. Clean up previous run
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER route_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# 3. Create schema
echo "Creating route_analyst user..."
oracle_query "CREATE USER route_analyst IDENTIFIED BY Route2024
  DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE MATERIALIZED VIEW, CREATE PROCEDURE, CREATE SESSION, CREATE TABLE TO route_analyst;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create route_analyst user"
    exit 1
fi

# 4. Create Tables and Insert Data
echo "Creating tables and loading OpenFlights realistic subset..."
sudo docker exec -i oracle-xe sqlplus -s route_analyst/Route2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE airports (
    airport_id      NUMBER PRIMARY KEY,
    iata_code       VARCHAR2(3) UNIQUE,
    airport_name    VARCHAR2(200),
    city            VARCHAR2(100),
    latitude        NUMBER,
    longitude       NUMBER
);

CREATE TABLE airlines (
    airline_id      NUMBER PRIMARY KEY,
    iata_code       VARCHAR2(3) UNIQUE,
    airline_name    VARCHAR2(100)
);

CREATE TABLE routes (
    route_id        NUMBER PRIMARY KEY,
    airline_id      NUMBER REFERENCES airlines(airline_id),
    source_airport_id NUMBER REFERENCES airports(airport_id),
    dest_airport_id   NUMBER REFERENCES airports(airport_id)
);

-- Sequences
CREATE SEQUENCE route_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE anomaly_seq START WITH 1 INCREMENT BY 1;

-- Insert Airlines
INSERT INTO airlines VALUES (1, 'AA', 'American Airlines');
INSERT INTO airlines VALUES (2, 'DL', 'Delta Air Lines');
INSERT INTO airlines VALUES (3, 'UA', 'United Airlines');
INSERT INTO airlines VALUES (4, 'WN', 'Southwest Airlines');
INSERT INTO airlines VALUES (5, 'AS', 'Alaska Airlines');

-- Insert Airports (Top US Hubs + some isolated)
INSERT INTO airports VALUES (1, 'ATL', 'Hartsfield Jackson Atlanta', 'Atlanta', 33.6367, -84.4281);
INSERT INTO airports VALUES (2, 'ORD', 'Chicago OHare', 'Chicago', 41.9786, -87.9048);
INSERT INTO airports VALUES (3, 'DFW', 'Dallas Fort Worth', 'Dallas', 32.8968, -97.0380);
INSERT INTO airports VALUES (4, 'DEN', 'Denver Intl', 'Denver', 39.8617, -104.6731);
INSERT INTO airports VALUES (5, 'LAX', 'Los Angeles Intl', 'Los Angeles', 33.9425, -118.4081);
INSERT INTO airports VALUES (6, 'JFK', 'John F Kennedy Intl', 'New York', 40.6398, -73.7789);
INSERT INTO airports VALUES (7, 'SFO', 'San Francisco Intl', 'San Francisco', 37.6189, -122.3750);
INSERT INTO airports VALUES (8, 'SEA', 'Seattle Tacoma Intl', 'Seattle', 47.4490, -122.3093);
INSERT INTO airports VALUES (9, 'LAS', 'McCarran Intl', 'Las Vegas', 36.0801, -115.1522);
INSERT INTO airports VALUES (10, 'MCO', 'Orlando Intl', 'Orlando', 28.4294, -81.3090);
INSERT INTO airports VALUES (11, 'MIA', 'Miami Intl', 'Miami', 25.7932, -80.2906);
INSERT INTO airports VALUES (12, 'HNL', 'Daniel K Inouye Intl', 'Honolulu', 21.3187, -157.9224);
INSERT INTO airports VALUES (13, 'SJU', 'Luis Munoz Marin Intl', 'San Juan', 18.4394, -66.0018);
INSERT INTO airports VALUES (14, 'ANC', 'Ted Stevens Anchorage', 'Anchorage', 61.1743, -149.9960);
INSERT INTO airports VALUES (15, 'FAI', 'Fairbanks Intl', 'Fairbanks', 64.8151, -147.8560);
INSERT INTO airports VALUES (16, 'LGA', 'LaGuardia', 'New York', 40.7772, -73.8726);
INSERT INTO airports VALUES (17, 'BOS', 'Logan Intl', 'Boston', 42.3643, -71.0052);
INSERT INTO airports VALUES (18, 'DCA', 'Ronald Reagan Washington', 'Washington', 38.8521, -77.0377);

-- Insert Routes
-- Helper: insert bidirectional route
BEGIN
  FOR a IN 1..4 LOOP -- 4 airlines
    -- Main Hub Connections (Bidirectional)
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 1, 2); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 2, 1); -- ATL-ORD
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 2, 3); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 3, 2); -- ORD-DFW
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 3, 5); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 5, 3); -- DFW-LAX
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 5, 7); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 7, 5); -- LAX-SFO
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 2, 6); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 6, 2); -- ORD-JFK
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 1, 10); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 10, 1); -- ATL-MCO
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 2, 4); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 4, 2); -- ORD-DEN
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 4, 8); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 8, 4); -- DEN-SEA
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 5, 12); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 12, 5); -- LAX-HNL
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 6, 17); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 17, 6); -- JFK-BOS
    INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 1, 11); INSERT INTO routes VALUES (route_seq.NEXTVAL, a, 11, 1); -- ATL-MIA
  END LOOP;
END;
/

-- Isolated component: Alaska
INSERT INTO routes VALUES (route_seq.NEXTVAL, 5, 14, 15); -- ANC-FAI
INSERT INTO routes VALUES (route_seq.NEXTVAL, 5, 15, 14); -- FAI-ANC

-- Asymmetric routes for anomaly detection
INSERT INTO routes VALUES (route_seq.NEXTVAL, 1, 11, 13); -- MIA to SJU (AA), but no return
INSERT INTO routes VALUES (route_seq.NEXTVAL, 3, 2, 16);  -- ORD to LGA (UA), but no return

COMMIT;
EXIT;
EOSQL
echo "Data loaded successfully."

# 5. Pre-configure SQL Developer connection for route_analyst
ensure_hr_connection "Route Network DB" "route_analyst" "Route2024"

# 6. Open SQL Developer
open_hr_connection_in_sqldeveloper

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="