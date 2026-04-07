#!/bin/bash
# Setup script for Spatial Coverage Analysis task
# Creates tables with legacy coordinate data (Lat/Lon)

set -e

echo "=== Setting up Spatial Coverage Analysis Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight checks ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

echo "[2/4] Verifying database connectivity..."
# Simple connectivity check
oracle_query "SELECT 1 FROM DUAL;" "hr" > /dev/null

# --- Clean up old artifacts ---
echo "[3/4] Cleaning up previous task artifacts..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE proposed_sites PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE existing_towers PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
DELETE FROM user_sdo_geom_metadata WHERE table_name IN ('EXISTING_TOWERS', 'PROPOSED_SITES');
COMMIT;
" "hr" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/priority_expansion_sites.txt

# --- Create Tables and Insert Data ---
echo "[4/4] Creating tables and loading data..."

# Towers: Major landmarks in Northeast US
# Sites: Mix of locations <25km (Serviced) and >25km (Unserviced) from these towers

oracle_query "
CREATE TABLE existing_towers (
    tower_id NUMBER PRIMARY KEY,
    tower_name VARCHAR2(100),
    city VARCHAR2(100),
    state VARCHAR2(2),
    latitude NUMBER(10, 6),
    longitude NUMBER(10, 6)
);

CREATE TABLE proposed_sites (
    site_id NUMBER PRIMARY KEY,
    site_name VARCHAR2(100),
    city VARCHAR2(100),
    state VARCHAR2(2),
    latitude NUMBER(10, 6),
    longitude NUMBER(10, 6)
);

-- EXISTING TOWERS (The Coverage Network)
INSERT INTO existing_towers VALUES (1, 'One World Trade Center', 'New York', 'NY', 40.7127, -74.0134);
INSERT INTO existing_towers VALUES (2, 'Empire State Building', 'New York', 'NY', 40.7484, -73.9857);
INSERT INTO existing_towers VALUES (3, 'Prudential Tower', 'Boston', 'MA', 42.3471, -71.0825);
INSERT INTO existing_towers VALUES (4, 'Comcast Center', 'Philadelphia', 'PA', 39.9549, -75.1685);
INSERT INTO existing_towers VALUES (5, 'White House', 'Washington', 'DC', 38.8977, -77.0365);
INSERT INTO existing_towers VALUES (6, 'Newark Airport Tower', 'Newark', 'NJ', 40.6895, -74.1745);
INSERT INTO existing_towers VALUES (7, 'LaGuardia Airport Tower', 'New York', 'NY', 40.7769, -73.8740);
INSERT INTO existing_towers VALUES (8, 'MIT Green Building', 'Cambridge', 'MA', 42.3601, -71.0942);
INSERT INTO existing_towers VALUES (9, 'Baltimore World Trade', 'Baltimore', 'MD', 39.2858, -76.6131);
INSERT INTO existing_towers VALUES (10, 'Stamford Train Station', 'Stamford', 'CT', 41.0460, -73.5420);

-- PROPOSED SITES - SERVICED (<25km from a tower)
INSERT INTO proposed_sites VALUES (101, 'Times Square Billboard', 'New York', 'NY', 40.7580, -73.9855); -- Near Empire State
INSERT INTO proposed_sites VALUES (102, 'Central Park Zoo', 'New York', 'NY', 40.7678, -73.9718); -- Near Empire State
INSERT INTO proposed_sites VALUES (103, 'Fenway Park Light', 'Boston', 'MA', 42.3467, -71.0972); -- Near Prudential
INSERT INTO proposed_sites VALUES (104, 'Logan Airport Terminal', 'Boston', 'MA', 42.3656, -71.0096); -- Near Prudential
INSERT INTO proposed_sites VALUES (105, 'Independence Hall', 'Philadelphia', 'PA', 39.9489, -75.1500); -- Near Comcast
INSERT INTO proposed_sites VALUES (106, 'The Pentagon', 'Arlington', 'VA', 38.8719, -77.0563); -- Near White House
INSERT INTO proposed_sites VALUES (107, 'Brooklyn Bridge Park', 'New York', 'NY', 40.7009, -73.9969); -- Near WTC
INSERT INTO proposed_sites VALUES (108, 'Jersey City Waterfront', 'Jersey City', 'NJ', 40.7178, -74.0431); -- Near WTC
INSERT INTO proposed_sites VALUES (109, 'Harvard Yard', 'Cambridge', 'MA', 42.3744, -71.1169); -- Near MIT
INSERT INTO proposed_sites VALUES (110, 'Greenwich Point', 'Greenwich', 'CT', 41.0116, -73.5804); -- Near Stamford

-- PROPOSED SITES - UNSERVICED (>25km from any tower)
-- These should appear in the output file
INSERT INTO proposed_sites VALUES (201, 'Albany Downtown', 'Albany', 'NY', 42.6526, -73.7562);
INSERT INTO proposed_sites VALUES (202, 'Montauk Point', 'Montauk', 'NY', 41.0706, -71.8562);
INSERT INTO proposed_sites VALUES (203, 'Harrisburg Capitol', 'Harrisburg', 'PA', 40.2644, -76.8836);
INSERT INTO proposed_sites VALUES (204, 'Atlantic City Boardwalk', 'Atlantic City', 'NJ', 39.3643, -74.4229);
INSERT INTO proposed_sites VALUES (205, 'Providence Waterplace', 'Providence', 'RI', 41.8240, -71.4128);
INSERT INTO proposed_sites VALUES (206, 'New Haven Green', 'New Haven', 'CT', 41.3082, -72.9279);
INSERT INTO proposed_sites VALUES (207, 'Syracuse University', 'Syracuse', 'NY', 43.0392, -76.1351);
INSERT INTO proposed_sites VALUES (208, 'Buffalo Waterfront', 'Buffalo', 'NY', 42.8775, -78.8797);
INSERT INTO proposed_sites VALUES (209, 'Portland Old Port', 'Portland', 'ME', 43.6591, -70.2568);
INSERT INTO proposed_sites VALUES (210, 'Burlington Church St', 'Burlington', 'VT', 44.4759, -73.2121);

COMMIT;
" "hr" > /dev/null 2>&1

# Record start time
date +%s > /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Tables EXISTING_TOWERS and PROPOSED_SITES created."
echo "Agent must add spatial columns and perform analysis."