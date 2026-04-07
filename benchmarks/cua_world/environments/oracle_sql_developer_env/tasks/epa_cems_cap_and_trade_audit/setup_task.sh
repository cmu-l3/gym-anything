#!/bin/bash
echo "=== Setting up EPA CEMS Cap-and-Trade Audit Task ==="

source /workspace/scripts/task_utils.sh

date +%s > /home/ga/.task_start_time

# Verify container
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null || echo "not_found")
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# Cleanup
echo "Setting up EPA_AUDIT schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER epa_audit CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# Create user
oracle_query "CREATE USER epa_audit IDENTIFIED BY Audit2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE TO epa_audit;
GRANT CREATE VIEW TO epa_audit;
GRANT CREATE TABLE TO epa_audit;
GRANT CREATE SESSION TO epa_audit;
EXIT;" "system"

# Execute table creation and population
sudo docker exec -i oracle-xe sqlplus -s epa_audit/Audit2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE facilities (
    facility_id NUMBER PRIMARY KEY,
    facility_name VARCHAR2(100),
    state VARCHAR2(2),
    primary_fuel VARCHAR2(50),
    operating_status VARCHAR2(20)
);

CREATE TABLE hourly_cems (
    facility_id NUMBER REFERENCES facilities(facility_id),
    op_date DATE,
    op_hour NUMBER,
    gross_load_mw NUMBER,
    co2_mass_tons NUMBER,
    PRIMARY KEY (facility_id, op_date, op_hour)
);

CREATE TABLE allowance_accounts (
    account_id NUMBER PRIMARY KEY,
    facility_id NUMBER REFERENCES facilities(facility_id),
    compliance_year NUMBER,
    initial_allocation NUMBER
);

CREATE TABLE allowance_trades (
    trade_id NUMBER PRIMARY KEY,
    seller_account_id NUMBER REFERENCES allowance_accounts(account_id),
    buyer_account_id NUMBER REFERENCES allowance_accounts(account_id),
    trade_date DATE,
    allowance_amount NUMBER
);

-- Insert Data
INSERT INTO facilities VALUES (101, 'Plant Scherer', 'GA', 'Coal', 'Operating');
INSERT INTO facilities VALUES (102, 'WA Parish', 'TX', 'Natural Gas', 'Operating');
INSERT INTO facilities VALUES (103, 'Monroe Power', 'MI', 'Coal', 'Operating');
INSERT INTO facilities VALUES (104, 'Bowen', 'GA', 'Coal', 'Operating');
INSERT INTO facilities VALUES (999, 'External Market', 'NA', 'None', 'Operating');

-- Hourly CEMS
-- Facility 101: 4000 total (compliant)
INSERT INTO hourly_cems VALUES (101, DATE '2023-01-01', 1, 300, 1000);
INSERT INTO hourly_cems VALUES (101, DATE '2023-01-01', 2, 300, 1000);
INSERT INTO hourly_cems VALUES (101, DATE '2023-01-01', 3, 300, 1000);
INSERT INTO hourly_cems VALUES (101, DATE '2023-01-01', 4, 300, 1000);

-- Facility 102: 5500 total (imputed)
INSERT INTO hourly_cems VALUES (102, DATE '2023-01-01', 1, 300, 1000);
INSERT INTO hourly_cems VALUES (102, DATE '2023-01-01', 2, 300, 1500);
INSERT INTO hourly_cems VALUES (102, DATE '2023-01-01', 3, 300, NULL);
INSERT INTO hourly_cems VALUES (102, DATE '2023-01-01', 4, 300, NULL);

-- Facility 103: 6000 total (imputed)
INSERT INTO hourly_cems VALUES (103, DATE '2023-01-01', 1, 300, 1000);
INSERT INTO hourly_cems VALUES (103, DATE '2023-01-01', 2, 300, NULL);
INSERT INTO hourly_cems VALUES (103, DATE '2023-01-01', 3, 300, 2000);
INSERT INTO hourly_cems VALUES (103, DATE '2023-01-01', 4, 300, NULL);

-- Facility 104: 8000 total (imputed)
INSERT INTO hourly_cems VALUES (104, DATE '2023-01-01', 1, 300, 2000);
INSERT INTO hourly_cems VALUES (104, DATE '2023-01-01', 2, 300, 2000);
INSERT INTO hourly_cems VALUES (104, DATE '2023-01-01', 3, 300, 2000);
INSERT INTO hourly_cems VALUES (104, DATE '2023-01-01', 4, 300, NULL);

-- Accounts
INSERT INTO allowance_accounts VALUES (1, 101, 2023, 5000);
INSERT INTO allowance_accounts VALUES (2, 102, 2023, 6000);
INSERT INTO allowance_accounts VALUES (3, 103, 2023, 5000);
INSERT INTO allowance_accounts VALUES (4, 104, 2023, 8000);
INSERT INTO allowance_accounts VALUES (9, 999, 2023, 100000);

-- Trades
INSERT INTO allowance_trades VALUES (1, 2, 9, DATE '2023-06-01', 1000);
INSERT INTO allowance_trades VALUES (2, 9, 4, DATE '2023-07-01', 500);
INSERT INTO allowance_trades VALUES (3, 4, 9, DATE '2023-08-01', 1000);

COMMIT;
EXIT;
EOSQL

echo "Data populated successfully."

# Setup connection in SQL Developer
mkdir -p /home/ga/.sqldeveloper/system24.3.0.284.2209/o.jdeveloper.db.connection.24.2.0.284.2209
CONN_FILE="/home/ga/.sqldeveloper/system24.3.0.284.2209/o.jdeveloper.db.connection.24.2.0.284.2209/connections.json"
cat > "$CONN_FILE" << 'CONNEOF'
{
  "connections": [
    {
      "name": "EPA Audit",
      "type": "jdbc",
      "info": {
        "role": "",
        "SavePassword": "true",
        "OracleConnectionType": "BASIC",
        "RaptorConnectionType": "Oracle",
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "hostname": "localhost",
        "driver": "oracle.jdbc.OracleDriver",
        "port": "1521",
        "subtype": "oraJDBC",
        "ConnName": "EPA Audit",
        "serviceName": "XEPDB1",
        "user": "epa_audit",
        "password": "Audit2024"
      }
    }
  ]
}
CONNEOF
chown -R ga:ga /home/ga/.sqldeveloper

# Prepare export directory
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/epa_penalties.csv 2>/dev/null || true

# Maximize SQL Developer window if it's already running
DISPLAY=:1 wmctrl -r "Oracle SQL Developer" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="