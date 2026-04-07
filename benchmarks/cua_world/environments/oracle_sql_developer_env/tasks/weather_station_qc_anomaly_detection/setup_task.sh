#!/bin/bash
# Setup script for Weather Station QC Anomaly Detection task
echo "=== Setting up Weather Station QC Anomaly Detection ==="

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
  EXECUTE IMMEDIATE 'DROP USER weather_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# ---------------------------------------------------------------
# 3. Create WEATHER_ANALYST schema
# ---------------------------------------------------------------
echo "Creating WEATHER_ANALYST schema..."
oracle_query "CREATE USER weather_analyst IDENTIFIED BY Weather2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO weather_analyst;
GRANT RESOURCE TO weather_analyst;
GRANT CREATE VIEW TO weather_analyst;
GRANT CREATE MATERIALIZED VIEW TO weather_analyst;
GRANT CREATE PROCEDURE TO weather_analyst;
GRANT CREATE SESSION TO weather_analyst;
GRANT CREATE TABLE TO weather_analyst;
GRANT CREATE SEQUENCE TO weather_analyst;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create weather_analyst user"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Create tables and generate synthetic historical data
# ---------------------------------------------------------------
echo "Creating schema tables and injecting data..."

sudo docker exec -i oracle-xe sqlplus -s weather_analyst/Weather2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE SEQUENCE obs_seq START WITH 1 INCREMENT BY 1 NOCACHE;

CREATE TABLE stations (
    station_id    VARCHAR2(20) PRIMARY KEY,
    station_name  VARCHAR2(100) NOT NULL,
    latitude      NUMBER(8,4) NOT NULL,
    longitude     NUMBER(9,4) NOT NULL,
    elevation_m   NUMBER(7,1),
    state         VARCHAR2(2),
    county        VARCHAR2(50),
    wmo_id        VARCHAR2(10),
    commissioned_date DATE
);

CREATE TABLE daily_observations (
    obs_id           NUMBER PRIMARY KEY,
    station_id       VARCHAR2(20) REFERENCES stations(station_id),
    obs_date         DATE NOT NULL,
    element          VARCHAR2(4) NOT NULL,
    value_raw        NUMBER(10,1) NOT NULL,
    measurement_flag VARCHAR2(1),
    quality_flag     VARCHAR2(1),
    source_flag      VARCHAR2(1),
    CONSTRAINT unq_obs UNIQUE (station_id, obs_date, element)
);

CREATE TABLE sensor_log (
    log_id       NUMBER PRIMARY KEY,
    station_id   VARCHAR2(20),
    element      VARCHAR2(4),
    event_type   VARCHAR2(30),
    event_date   DATE,
    description  VARCHAR2(500)
);

CREATE TABLE qc_flag_definitions (
    flag_code        VARCHAR2(20) PRIMARY KEY,
    flag_description VARCHAR2(200),
    severity         VARCHAR2(10)
);

INSERT INTO qc_flag_definitions VALUES ('STUCK_SENSOR', 'Sensor reporting identical value for >= 10 days', 'HIGH');
INSERT INTO qc_flag_definitions VALUES ('IMPOSSIBLE_VALUE', 'Physically impossible or out of bounds value', 'CRITICAL');
INSERT INTO qc_flag_definitions VALUES ('SPATIAL_ANOMALY', 'Value departs significantly from neighbors', 'MEDIUM');
COMMIT;

-- Generate 1 year of data for 30 stations using PL/SQL
DECLARE
  v_date DATE;
  v_tmax NUMBER;
  v_tmin NUMBER;
  v_prcp NUMBER;
  v_station VARCHAR2(20);
  v_lat NUMBER;
  v_lon NUMBER;
BEGIN
  -- 30 Stations
  FOR i IN 1..30 LOOP
    v_station := 'USW000900' || LPAD(i, 2, '0');
    v_lat := 40.0 + (i * 0.1);
    v_lon := -74.0 + (i * 0.1);
    
    INSERT INTO stations VALUES (v_station, 'NORTHEAST STATION '||i, v_lat, v_lon, 10 + i*5, 'NY', 'COUNTY_'||i, 'WMO'||i, DATE '2000-01-01');

    -- 365 days in 2023
    FOR d IN 1..365 LOOP
      v_date := DATE '2023-01-01' + (d - 1);
      
      -- Baseline seasonal temperature curve (sine wave)
      -- TMAX ranges ~ -5C to +35C (-50 to 350 in tenths)
      v_tmax := 150 + 200 * SIN((d - 100) / 365.0 * 2 * 3.14159);
      v_tmin := v_tmax - 90; -- 9C diurnal range
      v_prcp := CASE WHEN MOD(d*i, 11) = 0 THEN 45 + MOD(d, 100) ELSE 0 END;

      -- Inject Errors!
      
      -- 1. Impossible values
      IF MOD(d*i, 257) = 0 THEN
        v_tmax := -950; -- Less than -90C (impossible)
      END IF;
      
      IF MOD(d*i, 311) = 0 THEN
        v_tmin := v_tmax + 50; -- TMIN > TMAX (impossible)
      END IF;
      
      IF MOD(d*i, 401) = 0 THEN
        v_prcp := -20; -- Negative precipitation (impossible)
      END IF;

      -- 2. Stuck sensor (Station 1, TMAX stuck at 222 for 45 days in summer)
      IF i = 1 AND d BETWEEN 150 AND 194 THEN
        v_tmax := 222; 
      END IF;

      INSERT INTO daily_observations VALUES (obs_seq.nextval, v_station, v_date, 'TMAX', ROUND(v_tmax), NULL, NULL, '0');
      INSERT INTO daily_observations VALUES (obs_seq.nextval, v_station, v_date, 'TMIN', ROUND(v_tmin), NULL, NULL, '0');
      INSERT INTO daily_observations VALUES (obs_seq.nextval, v_station, v_date, 'PRCP', ROUND(v_prcp), NULL, NULL, '0');
    END LOOP;
  END LOOP;
  COMMIT;
END;
/
EXIT;
EOSQL

echo "Database schema and synthetic data loaded successfully."

# ---------------------------------------------------------------
# 5. Configure SQL Developer and Launch
# ---------------------------------------------------------------
echo "Configuring SQL Developer connection..."
ensure_hr_connection "Weather DB" "weather_analyst" "Weather2024"

rm -f /home/ga/climate_summary.csv 2>/dev/null || true

# Kill any existing SQL Developer
pkill -f sqldeveloper 2>/dev/null || true
sleep 2

echo "Launching SQL Developer..."
su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &"

# Wait for window to appear
echo "Waiting for SQL Developer window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
        echo "SQL Developer window detected."
        break
    fi
    sleep 1
done

sleep 5

# Maximize SQL Developer
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Open the connection
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="