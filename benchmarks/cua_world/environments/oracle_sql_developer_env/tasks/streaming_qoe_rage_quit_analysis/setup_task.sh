#!/bin/bash
# Setup script for Streaming QoE & Rage Quit Analysis task
echo "=== Setting up Streaming QoE & Rage Quit Analysis Task ==="

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

# Wait for Oracle to be ready
echo "Waiting for Oracle database listener..."
for i in {1..30}; do
    if oracle_query_raw "SELECT 1 FROM DUAL;" "system" > /dev/null 2>&1; then
        break
    fi
    sleep 2
done

# ---------------------------------------------------------------
# 2. Clean up previous run artifacts
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER stream_sre CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Create STREAM_SRE schema and grant privileges
# ---------------------------------------------------------------
echo "Creating STREAM_SRE schema..."

oracle_query "CREATE USER stream_sre IDENTIFIED BY Stream2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO stream_sre;
GRANT RESOURCE TO stream_sre;
GRANT CREATE VIEW TO stream_sre;
GRANT CREATE MATERIALIZED VIEW TO stream_sre;
GRANT CREATE PROCEDURE TO stream_sre;
GRANT CREATE SESSION TO stream_sre;
GRANT CREATE TABLE TO stream_sre;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create stream_sre user"
    exit 1
fi
echo "stream_sre user created with required privileges"

# ---------------------------------------------------------------
# 4. Create Tables and Insert Data
# ---------------------------------------------------------------
echo "Creating tables and inserting telemetry data..."

sudo docker exec -i oracle-xe sqlplus -s stream_sre/Stream2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE cdn_nodes (
  node_id        VARCHAR2(50) PRIMARY KEY,
  region         VARCHAR2(50),
  provider       VARCHAR2(50),
  ip_range       VARCHAR2(50),
  active_status  NUMBER(1)
);

CREATE TABLE subscribers (
  sub_id         VARCHAR2(50) PRIMARY KEY,
  isp_name       VARCHAR2(100),
  state          VARCHAR2(50),
  plan_tier      VARCHAR2(50),
  signup_date    DATE
);

CREATE TABLE raw_client_telemetry (
  event_id         NUMBER PRIMARY KEY,
  sub_id           VARCHAR2(50) REFERENCES subscribers(sub_id),
  session_id       VARCHAR2(50),
  event_timestamp  TIMESTAMP,
  raw_json_payload CLOB,
  CONSTRAINT ensure_json CHECK (raw_json_payload IS JSON)
);

-- Insert CDN Nodes
INSERT INTO cdn_nodes VALUES ('EDGE-USEAST-12', 'US-East', 'AWS', '192.168.1.x', 1);
INSERT INTO cdn_nodes VALUES ('EDGE-USWEST-01', 'US-West', 'Akamai', '10.0.0.x', 1);

-- Insert Subscribers
INSERT INTO subscribers VALUES ('SUB1', 'Comcast', 'Active', 'Premium', DATE '2023-01-01');
INSERT INTO subscribers VALUES ('SUB2', 'Verizon', 'Active', 'Standard', DATE '2023-05-15');
INSERT INTO subscribers VALUES ('SUB3', 'AT&T', 'Active', 'Premium', DATE '2022-11-20');

-- Insert deterministic planted test sessions
-- S1: Normal smooth session. PLAYING duration = 595s.
INSERT INTO raw_client_telemetry VALUES (1, 'SUB1', 'S1', TIMESTAMP '2024-11-01 20:00:00', '{"player_state": "START", "bitrate_kbps": 0, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 0}');
INSERT INTO raw_client_telemetry VALUES (2, 'SUB1', 'S1', TIMESTAMP '2024-11-01 20:00:05', '{"player_state": "PLAYING", "bitrate_kbps": 4500, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 4000}');
INSERT INTO raw_client_telemetry VALUES (3, 'SUB1', 'S1', TIMESTAMP '2024-11-01 20:10:00', '{"player_state": "STOP", "bitrate_kbps": 4500, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 4000}');

-- S2: TRUE Rage Quit (Time between first BUFFERING and ABORT = 60s, <= 120s limit)
INSERT INTO raw_client_telemetry VALUES (4, 'SUB2', 'S2', TIMESTAMP '2024-11-01 20:15:00', '{"player_state": "START", "bitrate_kbps": 0, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 0}');
INSERT INTO raw_client_telemetry VALUES (5, 'SUB2', 'S2', TIMESTAMP '2024-11-01 20:15:05', '{"player_state": "PLAYING", "bitrate_kbps": 4500, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 4000}');
INSERT INTO raw_client_telemetry VALUES (6, 'SUB2', 'S2', TIMESTAMP '2024-11-01 20:20:00', '{"player_state": "BUFFERING", "bitrate_kbps": 500, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 100}');
INSERT INTO raw_client_telemetry VALUES (7, 'SUB2', 'S2', TIMESTAMP '2024-11-01 20:20:30', '{"player_state": "BUFFERING", "bitrate_kbps": 200, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 0}');
INSERT INTO raw_client_telemetry VALUES (8, 'SUB2', 'S2', TIMESTAMP '2024-11-01 20:21:00', '{"player_state": "ABORT", "bitrate_kbps": 0, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 0}');

-- S3: FALSE POSITIVE (Only 1 BUFFERING event before ABORT)
INSERT INTO raw_client_telemetry VALUES (9, 'SUB3', 'S3', TIMESTAMP '2024-11-01 20:30:00', '{"player_state": "START", "bitrate_kbps": 0, "cdn_node_id": "EDGE-USWEST-01", "buffer_health_ms": 0}');
INSERT INTO raw_client_telemetry VALUES (10, 'SUB3', 'S3', TIMESTAMP '2024-11-01 20:30:05', '{"player_state": "PLAYING", "bitrate_kbps": 4500, "cdn_node_id": "EDGE-USWEST-01", "buffer_health_ms": 4000}');
INSERT INTO raw_client_telemetry VALUES (11, 'SUB3', 'S3', TIMESTAMP '2024-11-01 20:35:00', '{"player_state": "BUFFERING", "bitrate_kbps": 500, "cdn_node_id": "EDGE-USWEST-01", "buffer_health_ms": 100}');
INSERT INTO raw_client_telemetry VALUES (12, 'SUB3', 'S3', TIMESTAMP '2024-11-01 20:35:10', '{"player_state": "ABORT", "bitrate_kbps": 0, "cdn_node_id": "EDGE-USWEST-01", "buffer_health_ms": 0}');

-- S4: FALSE POSITIVE (Time between first BUFFERING and ABORT = 150s, which is > 120s limit)
INSERT INTO raw_client_telemetry VALUES (13, 'SUB1', 'S4', TIMESTAMP '2024-11-01 20:40:00', '{"player_state": "START", "bitrate_kbps": 0, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 0}');
INSERT INTO raw_client_telemetry VALUES (14, 'SUB1', 'S4', TIMESTAMP '2024-11-01 20:40:05', '{"player_state": "PLAYING", "bitrate_kbps": 4500, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 4000}');
INSERT INTO raw_client_telemetry VALUES (15, 'SUB1', 'S4', TIMESTAMP '2024-11-01 20:45:00', '{"player_state": "BUFFERING", "bitrate_kbps": 500, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 100}');
INSERT INTO raw_client_telemetry VALUES (16, 'SUB1', 'S4', TIMESTAMP '2024-11-01 20:46:00', '{"player_state": "BUFFERING", "bitrate_kbps": 200, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 0}');
INSERT INTO raw_client_telemetry VALUES (17, 'SUB1', 'S4', TIMESTAMP '2024-11-01 20:47:30', '{"player_state": "ABORT", "bitrate_kbps": 0, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 0}');

-- S5: TRUE Rage Quit (Another valid hit to ensure grouping logic works)
INSERT INTO raw_client_telemetry VALUES (18, 'SUB2', 'S5', TIMESTAMP '2024-11-01 20:50:00', '{"player_state": "START", "bitrate_kbps": 0, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 0}');
INSERT INTO raw_client_telemetry VALUES (19, 'SUB2', 'S5', TIMESTAMP '2024-11-01 20:50:05', '{"player_state": "PLAYING", "bitrate_kbps": 4500, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 4000}');
INSERT INTO raw_client_telemetry VALUES (20, 'SUB2', 'S5', TIMESTAMP '2024-11-01 20:52:00', '{"player_state": "BUFFERING", "bitrate_kbps": 500, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 100}');
INSERT INTO raw_client_telemetry VALUES (21, 'SUB2', 'S5', TIMESTAMP '2024-11-01 20:52:25', '{"player_state": "BUFFERING", "bitrate_kbps": 200, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 0}');
INSERT INTO raw_client_telemetry VALUES (22, 'SUB2', 'S5', TIMESTAMP '2024-11-01 20:52:45', '{"player_state": "ABORT", "bitrate_kbps": 0, "cdn_node_id": "EDGE-USEAST-12", "buffer_health_ms": 0}');

COMMIT;

-- Generate 25k noise events to represent real telemetry volume
BEGIN
  FOR i IN 1..25000 LOOP
     INSERT INTO raw_client_telemetry VALUES (
        100 + i,
        'SUB' || (MOD(i, 3) + 1),
        'S_NOISE_' || TRUNC(i/5),
        TIMESTAMP '2024-11-01 00:00:00' + NUMTODSINTERVAL(i, 'SECOND'),
        '{"player_state": "' || CASE MOD(i, 5) WHEN 0 THEN 'START' WHEN 1 THEN 'PLAYING' WHEN 2 THEN 'BUFFERING' WHEN 3 THEN 'PLAYING' ELSE 'STOP' END || '", "bitrate_kbps": 3000, "cdn_node_id": "EDGE-USWEST-01", "buffer_health_ms": 2000}'
     );
  END LOOP;
  COMMIT;
END;
/
EXIT;
EOSQL

echo "Data populated successfully."

# ---------------------------------------------------------------
# 5. Pre-configure SQL Developer Connection
# ---------------------------------------------------------------
# Configure the connection to STREAM_SRE schema
ensure_hr_connection "Streaming Telemetry" "stream_sre" "Stream2024"

# ---------------------------------------------------------------
# 6. Open SQL Developer
# ---------------------------------------------------------------
echo "Focusing SQL Developer window..."
# Focus window if already running, otherwise we rely on the framework to start it
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Connect to the configured schema if SQL Developer is running
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png ga

echo "=== Task Setup Complete ==="