#!/bin/bash
# Setup script for Smart City JSON Telemetry task
echo "=== Setting up Smart City JSON Telemetry Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# ---------------------------------------------------------------
# Clean up previous run artifacts
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER city_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# Create CITY_ANALYST schema
# ---------------------------------------------------------------
echo "Creating CITY_ANALYST schema..."

oracle_query "CREATE USER city_analyst IDENTIFIED BY CityData2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO city_analyst;
GRANT RESOURCE TO city_analyst;
GRANT CREATE VIEW TO city_analyst;
GRANT CREATE TABLE TO city_analyst;
GRANT CREATE SESSION TO city_analyst;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create city_analyst user"
    exit 1
fi

# ---------------------------------------------------------------
# Create staging table and populate with realistic JSON
# ---------------------------------------------------------------
echo "Creating METER_TELEMETRY_STG table and loading JSON data..."

sudo docker exec -i oracle-xe sqlplus -s city_analyst/CityData2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE meter_telemetry_stg (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payload CLOB
);

-- Insert normal heartbeats (10 rows)
BEGIN
  FOR i IN 1..10 LOOP
    INSERT INTO meter_telemetry_stg (payload) VALUES (
      '{"device_id": "MTR-' || (1000+i) || '", "timestamp": "2024-10-24T08:00:00Z", "event_type": "heartbeat", "battery_pct": ' || (90-i) || ', "hardware": {"status": "ok", "faults": []}}'
    );
  END LOOP;
END;
/

-- Insert normal payments (10 rows)
BEGIN
  FOR i IN 1..10 LOOP
    INSERT INTO meter_telemetry_stg (payload) VALUES (
      '{"device_id": "MTR-' || (2000+i) || '", "timestamp": "2024-10-24T09:00:00Z", "event_type": "payment_session", "battery_pct": 80, "session": {"reported_total": 5.00, "transactions": [{"method": "credit", "amount": 5.00}]}, "hardware": {"status": "ok", "faults": []}}'
    );
  END LOOP;
END;
/

-- Insert payments with discrepancies (5 rows)
INSERT INTO meter_telemetry_stg (payload) VALUES ('{"device_id": "MTR-3001", "timestamp": "2024-10-24T10:01:00Z", "event_type": "payment_session", "battery_pct": 75, "session": {"reported_total": 4.00, "transactions": [{"method": "coin", "amount": 1.00}, {"method": "coin", "amount": 2.00}]}, "hardware": {"status": "ok", "faults": []}}');
INSERT INTO meter_telemetry_stg (payload) VALUES ('{"device_id": "MTR-3002", "timestamp": "2024-10-24T10:02:00Z", "event_type": "payment_session", "battery_pct": 75, "session": {"reported_total": 6.50, "transactions": [{"method": "credit", "amount": 5.50}]}, "hardware": {"status": "ok", "faults": []}}');
INSERT INTO meter_telemetry_stg (payload) VALUES ('{"device_id": "MTR-3003", "timestamp": "2024-10-24T10:03:00Z", "event_type": "payment_session", "battery_pct": 75, "session": {"reported_total": 10.00, "transactions": [{"method": "credit", "amount": 5.00}, {"method": "credit", "amount": 3.00}]}, "hardware": {"status": "ok", "faults": []}}');
INSERT INTO meter_telemetry_stg (payload) VALUES ('{"device_id": "MTR-3004", "timestamp": "2024-10-24T10:04:00Z", "event_type": "payment_session", "battery_pct": 75, "session": {"reported_total": 2.00, "transactions": [{"method": "coin", "amount": 1.50}]}, "hardware": {"status": "ok", "faults": []}}');
INSERT INTO meter_telemetry_stg (payload) VALUES ('{"device_id": "MTR-3005", "timestamp": "2024-10-24T10:05:00Z", "event_type": "payment_session", "battery_pct": 75, "session": {"reported_total": 5.00, "transactions": [{"method": "credit", "amount": 4.00}]}, "hardware": {"status": "ok", "faults": []}}');

-- Insert hardware faults (5 rows, total 8 fault elements)
INSERT INTO meter_telemetry_stg (payload) VALUES ('{"device_id": "MTR-4001", "timestamp": "2024-10-24T11:01:00Z", "event_type": "hardware_alert", "battery_pct": 20, "hardware": {"status": "error", "faults": ["F_LOW_BATTERY"]}}');
INSERT INTO meter_telemetry_stg (payload) VALUES ('{"device_id": "MTR-4002", "timestamp": "2024-10-24T11:02:00Z", "event_type": "hardware_alert", "battery_pct": 80, "hardware": {"status": "error", "faults": ["F_COIN_JAM", "F_SENSOR_FAIL"]}}');
INSERT INTO meter_telemetry_stg (payload) VALUES ('{"device_id": "MTR-4003", "timestamp": "2024-10-24T11:03:00Z", "event_type": "hardware_alert", "battery_pct": 85, "hardware": {"status": "warning", "faults": ["F_PRINTER_PAPER_LOW"]}}');
INSERT INTO meter_telemetry_stg (payload) VALUES ('{"device_id": "MTR-4004", "timestamp": "2024-10-24T11:04:00Z", "event_type": "hardware_alert", "battery_pct": 15, "hardware": {"status": "error", "faults": ["F_LOW_BATTERY", "F_MODEM_OFFLINE"]}}');
INSERT INTO meter_telemetry_stg (payload) VALUES ('{"device_id": "MTR-4005", "timestamp": "2024-10-24T11:05:00Z", "event_type": "hardware_alert", "battery_pct": 90, "hardware": {"status": "error", "faults": ["F_COIN_JAM", "F_PRINTER_ERROR"]}}');

COMMIT;
EXIT;
EOSQL

echo "Data populated successfully."

# ---------------------------------------------------------------
# Prepare Environment
# ---------------------------------------------------------------
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/maintenance_dispatch.csv

# Pre-configure SQL Developer connection to avoid Welcome screen
ensure_hr_connection "City Analyst" "city_analyst" "CityData2024"

# Open SQL Developer if not already running
if ! pgrep -f "sqldeveloper" > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &"
    sleep 15
fi

open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="