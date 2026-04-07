#!/bin/bash
echo "=== Setting up Maritime AIS Port Congestion ==="

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
# 2. Clean up previous run artifacts (idempotent re-runs)
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER marine_ops CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Create MARINE_OPS schema
# ---------------------------------------------------------------
echo "Creating MARINE_OPS schema..."

oracle_query "CREATE USER marine_ops IDENTIFIED BY Marine2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO marine_ops;
GRANT RESOURCE TO marine_ops;
GRANT CREATE VIEW TO marine_ops;
GRANT CREATE MATERIALIZED VIEW TO marine_ops;
GRANT CREATE PROCEDURE TO marine_ops;
GRANT CREATE JOB TO marine_ops;
GRANT CREATE SESSION TO marine_ops;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create marine_ops user"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Create tables and insert deterministic test data
# ---------------------------------------------------------------
echo "Creating schema tables and inserting mock data..."

sudo docker exec -i oracle-xe sqlplus -s marine_ops/Marine2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE vessels (
    mmsi          NUMBER PRIMARY KEY,
    vessel_name   VARCHAR2(100),
    vessel_type   VARCHAR2(50),
    length        NUMBER,
    width         NUMBER
);

CREATE TABLE port_zones (
    zone_id       NUMBER PRIMARY KEY,
    zone_name     VARCHAR2(100),
    zone_type     VARCHAR2(50),
    min_lat       NUMBER,
    max_lat       NUMBER,
    min_lon       NUMBER,
    max_lon       NUMBER
);

CREATE TABLE ais_pings (
    ping_id        NUMBER PRIMARY KEY,
    mmsi           NUMBER REFERENCES vessels(mmsi),
    ping_timestamp TIMESTAMP,
    lat            NUMBER,
    lon            NUMBER,
    speed_knots    NUMBER
);

-- Insert Vessels
INSERT INTO vessels VALUES (1001, 'Ever Given', 'Cargo', 400, 59);
INSERT INTO vessels VALUES (1002, 'Seawise Giant', 'Tanker', 458, 68);
INSERT INTO vessels VALUES (1003, 'Symphony', 'Passenger', 362, 66);

-- Insert Zones
INSERT INTO port_zones VALUES (1, 'Alpha Anchorage', 'ANCHORAGE', 10.0, 20.0, 10.0, 20.0);
INSERT INTO port_zones VALUES (2, 'Beta Terminal', 'TERMINAL', 30.0, 40.0, 30.0, 40.0);

-- Insert Pings: MMSI 1001 (Valid gaps and islands: 2 Anchorage stays, 1 Terminal stay)
-- Sequence: Out -> Anchorage -> Out -> Terminal -> Out -> Anchorage
INSERT INTO ais_pings VALUES (1, 1001, TIMESTAMP '2024-05-01 10:00:00', 5, 5, 12); -- OUT
INSERT INTO ais_pings VALUES (2, 1001, TIMESTAMP '2024-05-01 11:00:00', 15, 15, 0); -- ANC 1 Start
INSERT INTO ais_pings VALUES (3, 1001, TIMESTAMP '2024-05-01 12:00:00', 15, 15, 0); -- ANC 1 End
INSERT INTO ais_pings VALUES (4, 1001, TIMESTAMP '2024-05-01 13:00:00', 25, 25, 8); -- OUT
INSERT INTO ais_pings VALUES (5, 1001, TIMESTAMP '2024-05-01 14:00:00', 35, 35, 0); -- TERM Start
INSERT INTO ais_pings VALUES (6, 1001, TIMESTAMP '2024-05-01 15:00:00', 35, 35, 0); -- TERM End
INSERT INTO ais_pings VALUES (7, 1001, TIMESTAMP '2024-05-01 16:00:00', 25, 25, 10); -- OUT
INSERT INTO ais_pings VALUES (8, 1001, TIMESTAMP '2024-05-01 17:00:00', 15, 15, 0); -- ANC 2 Start
INSERT INTO ais_pings VALUES (9, 1001, TIMESTAMP '2024-05-01 18:00:00', 15, 15, 0); -- ANC 2 End

-- Insert Pings: MMSI 1002 (1 Anchorage stay, 1 Terminal stay but terminal is > 24h later, invalid port call)
INSERT INTO ais_pings VALUES (10, 1002, TIMESTAMP '2024-05-01 08:00:00', 12, 12, 0); -- ANC Start
INSERT INTO ais_pings VALUES (11, 1002, TIMESTAMP '2024-05-01 09:00:00', 12, 12, 0); -- ANC End
INSERT INTO ais_pings VALUES (12, 1002, TIMESTAMP '2024-05-03 10:00:00', 32, 32, 0); -- TERM Start (>24h later)
INSERT INTO ais_pings VALUES (13, 1002, TIMESTAMP '2024-05-03 11:00:00', 32, 32, 0); -- TERM End

-- Insert Pings: MMSI 1003 (1 ping in anchorage, should be filtered out by "> 1 ping" rule)
INSERT INTO ais_pings VALUES (14, 1003, TIMESTAMP '2024-05-05 10:00:00', 18, 18, 0);

COMMIT;
EXIT;
EOSQL
echo "  Data inserted."

# ---------------------------------------------------------------
# 5. Pre-configure SQL Developer Connection
# ---------------------------------------------------------------
echo "Configuring SQL Developer connection..."
ensure_hr_connection "Marine Ops DB" "marine_ops" "Marine2024"

# ---------------------------------------------------------------
# 6. Ensure export directory exists
# ---------------------------------------------------------------
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# ---------------------------------------------------------------
# 7. Start SQL Developer
# ---------------------------------------------------------------
if ! pgrep -f "sqldeveloper" > /dev/null; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper > /dev/null 2>&1 &"
    sleep 20
fi

# Maximize and Focus SQL Developer
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

open_hr_connection_in_sqldeveloper

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="