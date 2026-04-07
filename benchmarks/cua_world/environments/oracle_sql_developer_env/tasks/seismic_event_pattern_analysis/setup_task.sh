#!/bin/bash
# Setup script for Seismic Event Pattern Analysis task
echo "=== Setting up Seismic Event Pattern Analysis ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# 1. Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# 2. Clean up previous run artifacts
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER seismo CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# 3. Create SEISMO schema
echo "Creating SEISMO schema..."
oracle_query "CREATE USER seismo IDENTIFIED BY Seismo2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO seismo;
GRANT RESOURCE TO seismo;
GRANT CREATE VIEW TO seismo;
GRANT CREATE PROCEDURE TO seismo;
GRANT CREATE JOB TO seismo;
GRANT CREATE SESSION TO seismo;
GRANT CREATE TABLE TO seismo;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create seismo user"
    exit 1
fi

# 4. Create base tables
echo "Creating SEISMO schema tables..."
sudo docker exec -i oracle-xe sqlplus -s seismo/Seismo2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE seismic_regions (
    region_id         NUMBER PRIMARY KEY,
    region_name       VARCHAR2(100) NOT NULL,
    min_lat           NUMBER(8,5),
    max_lat           NUMBER(8,5),
    min_lon           NUMBER(9,5),
    max_lon           NUMBER(9,5),
    tectonic_setting  VARCHAR2(100),
    historical_b_value NUMBER(4,2)
);

CREATE TABLE earthquake_catalog (
    event_id       VARCHAR2(20) PRIMARY KEY,
    event_time     TIMESTAMP NOT NULL,
    latitude       NUMBER(8,5) NOT NULL,
    longitude      NUMBER(9,5) NOT NULL,
    depth_km       NUMBER(6,2),
    magnitude      NUMBER(4,2) NOT NULL,
    mag_type       VARCHAR2(10),
    place          VARCHAR2(200),
    event_type     VARCHAR2(30),
    seismic_region VARCHAR2(100),
    review_status  VARCHAR2(20)
);

CREATE INDEX idx_eq_time ON earthquake_catalog(event_time);
CREATE INDEX idx_eq_region ON earthquake_catalog(seismic_region, event_time);

INSERT INTO seismic_regions VALUES (1, 'California', 32.0, 42.0, -125.0, -114.0, 'Transform', 1.0);
INSERT INTO seismic_regions VALUES (2, 'Alaska', 50.0, 72.0, -170.0, -130.0, 'Subduction', 0.9);
INSERT INTO seismic_regions VALUES (3, 'Hawaii', 18.0, 23.0, -160.0, -154.0, 'Hotspot', 1.2);
INSERT INTO seismic_regions VALUES (4, 'Other', -90.0, 90.0, -180.0, 180.0, 'Various', 1.0);
COMMIT;
EXIT;
EOSQL

# 5. Download REAL USGS Data and load it
echo "Downloading real USGS earthquake data (last 30 days of 2023)..."
USGS_URL="https://earthquake.usgs.gov/fdsnws/event/1/query?format=csv&starttime=2023-07-01&endtime=2023-08-01&minmagnitude=2.0&eventtype=earthquake&orderby=time"
curl -s "$USGS_URL" > /tmp/usgs_data.csv

# If download failed, use a small fallback dataset
if [ ! -s /tmp/usgs_data.csv ] || [ $(wc -l < /tmp/usgs_data.csv) -lt 10 ]; then
    echo "WARNING: USGS download failed. Using generated realistic fallback data."
    cat > /tmp/usgs_data.csv << 'EOF'
time,latitude,longitude,depth,mag,magType,nst,gap,dmin,rms,net,id,updated,place,type,horizontalError,depthError,magError,magNst,status,locationSource,magSource
2023-07-01T10:00:00.000Z,35.1,-118.1,5.0,2.5,ml,,,,,nc,nc1,2023-07-01,California,earthquake,,,,,,reviewed,nc,nc
2023-07-01T14:30:00.000Z,35.1,-118.1,5.0,5.5,mw,,,,,nc,nc2,2023-07-01,California,earthquake,,,,,,reviewed,nc,nc
2023-07-01T15:00:00.000Z,35.1,-118.1,5.0,3.2,ml,,,,,nc,nc3,2023-07-01,California,earthquake,,,,,,reviewed,nc,nc
2023-07-02T08:00:00.000Z,35.1,-118.1,5.0,2.8,ml,,,,,nc,nc4,2023-07-02,California,earthquake,,,,,,reviewed,nc,nc
2023-07-15T10:00:00.000Z,60.1,-150.1,15.0,3.5,ml,,,,,ak,ak1,2023-07-15,Alaska,earthquake,,,,,,reviewed,ak,ak
EOF
fi

echo "Converting CSV to SQL..."
cat << 'AWKEOF' > /tmp/convert_usgs.awk
BEGIN { FS=","; OFS=","; print "SET DEFINE OFF;\nWHENEVER SQLERROR CONTINUE;" }
NR>1 && $5 != "" {
    gsub(/T/, " ", $1); gsub(/Z/, "", $1);
    time = $1; lat = $2; lon = $3; depth = $4; mag = $5; magType = $6;
    id = $12; place = $14; type = $15; status = $20;
    
    region = "Other";
    if (lat >= 32 && lat <= 42 && lon >= -125 && lon <= -114) region = "California";
    else if (lat >= 50 && lat <= 72 && lon >= -170 && lon <= -130) region = "Alaska";
    else if (lat >= 18 && lat <= 23 && lon >= -160 && lon <= -154) region = "Hawaii";
    
    gsub(/'/, "''", place);
    if (length(time) > 10) {
        printf "INSERT INTO earthquake_catalog (event_id, event_time, latitude, longitude, depth_km, magnitude, mag_type, place, event_type, seismic_region, review_status) VALUES ('%s', TO_TIMESTAMP('%s', 'YYYY-MM-DD HH24:MI:SS.FF'), %s, %s, %s, %s, '%s', '%s', '%s', '%s', '%s');\n", id, time, lat, lon, depth, mag, magType, place, type, region, status;
    }
}
END { print "COMMIT;\nEXIT;" }
AWKEOF

awk -f /tmp/convert_usgs.awk /tmp/usgs_data.csv > /tmp/load_usgs.sql

echo "Loading earthquake data into Oracle..."
sudo docker exec -i oracle-xe sqlplus -s seismo/Seismo2024@//localhost:1521/XEPDB1 < /tmp/load_usgs.sql > /dev/null

DATA_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM earthquake_catalog;" "seismo" "Seismo2024" | tr -d '[:space:]')
echo "Loaded $DATA_COUNT real earthquake events."

# 6. Pre-configure SQL Developer Connection for the agent
ensure_hr_connection "Seismo Database" "seismo" "Seismo2024"

# 7. Launch SQL Developer (if not running) and open connection
if ! pgrep -f "sqldeveloper" > /dev/null; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 JAVA_TOOL_OPTIONS='--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED --add-opens=java.base/sun.net.www=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED -Dsun.java2d.xrender=false -Dsun.java2d.opengl=false' /opt/sqldeveloper/sqldeveloper.sh > /tmp/sqldeveloper.log 2>&1 &"
    
    sleep 20
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
            break
        fi
        sleep 1
    done
fi

open_hr_connection_in_sqldeveloper

# Maximize SQL Developer window
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="