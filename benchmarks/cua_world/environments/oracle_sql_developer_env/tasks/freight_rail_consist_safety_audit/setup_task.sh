#!/bin/bash
echo "=== Setting up Freight Rail Consist Safety Audit Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# 1. Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# 2. Clean up previous schema if exists
echo "Cleaning up database..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER rail_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# 3. Create RAIL_OPS schema (rail_admin user)
echo "Creating RAIL_ADMIN user..."
oracle_query "CREATE USER rail_admin IDENTIFIED BY Railroad2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO rail_admin;
GRANT RESOURCE TO rail_admin;
GRANT CREATE VIEW TO rail_admin;
GRANT CREATE MATERIALIZED VIEW TO rail_admin;
GRANT CREATE SESSION TO rail_admin;
GRANT CREATE TABLE TO rail_admin;
EXIT;" "system"

# 4. Create Tables and Insert Data
echo "Creating tables and populating manifest data..."
sudo docker exec -i oracle-xe sqlplus -s rail_admin/Railroad2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE locomotives (
    loco_id VARCHAR2(20) PRIMARY KEY,
    loco_model VARCHAR2(50),
    weight_tons NUMBER,
    hp NUMBER,
    max_trailing_tons NUMBER
);

CREATE TABLE railcars (
    car_id VARCHAR2(20) PRIMARY KEY,
    reporting_mark VARCHAR2(10),
    car_number VARCHAR2(20),
    car_type VARCHAR2(50),
    tare_weight_tons NUMBER,
    max_gross_weight_tons NUMBER
);

CREATE TABLE hazmat_ref (
    un_number VARCHAR2(20) PRIMARY KEY,
    proper_shipping_name VARCHAR2(100),
    hazard_class VARCHAR2(10),
    requires_buffer_flag VARCHAR2(1)
);

CREATE TABLE trains (
    train_symbol VARCHAR2(20) PRIMARY KEY,
    origin_terminal VARCHAR2(50),
    dest_terminal VARCHAR2(50),
    departure_time DATE,
    status VARCHAR2(20)
);

CREATE TABLE train_consist (
    consist_id NUMBER PRIMARY KEY,
    train_symbol VARCHAR2(20) REFERENCES trains(train_symbol),
    position_num NUMBER,
    equipment_type VARCHAR2(10),
    equipment_id VARCHAR2(20),
    is_loaded VARCHAR2(1),
    cargo_weight_tons NUMBER,
    un_number VARCHAR2(20) REFERENCES hazmat_ref(un_number)
);

-- Populate Locomotives
INSERT INTO locomotives VALUES ('ENG-1', 'GE ES44AC', 208, 4400, 5000);
INSERT INTO locomotives VALUES ('ENG-2', 'EMD SD70ACe', 204, 4300, 6000);

-- Populate Railcars
INSERT INTO railcars VALUES ('CAR-101', 'BNSF', 'BNSF1234', 'Hopper', 30, 143);
INSERT INTO railcars VALUES ('CAR-102', 'UTLX', 'UTLX5678', 'Tank', 35, 131);
INSERT INTO railcars VALUES ('CAR-103', 'TTGX', 'TTGX9901', 'Flat', 30, 143);
INSERT INTO railcars VALUES ('CAR-104', 'TTGX', 'TTGX9902', 'Flat', 30, 143);
INSERT INTO railcars VALUES ('CAR-105', 'TTGX', 'TTGX9903', 'Flat', 30, 143);

-- Populate Hazmat
INSERT INTO hazmat_ref VALUES ('UN1005', 'Ammonia, Anhydrous', '2.2', 'Y');
INSERT INTO hazmat_ref VALUES ('UN1203', 'Gasoline', '3', 'Y');
INSERT INTO hazmat_ref VALUES ('NONE', 'Non-Hazardous', 'N/A', 'N');

-- Populate Trains
INSERT INTO trains VALUES ('Q-CHILAA1', 'Chicago, IL', 'Los Angeles, CA', SYSDATE, 'BUILDING');
INSERT INTO trains VALUES ('M-CHIGAL1', 'Chicago, IL', 'Galesburg, IL', SYSDATE, 'BUILDING');
INSERT INTO trains VALUES ('U-COAL1', 'Powder River, WY', 'Chicago, IL', SYSDATE, 'BUILDING');
INSERT INTO trains VALUES ('Z-NYCCHI1', 'New York, NY', 'Chicago, IL', SYSDATE, 'BUILDING');

-- Train 1 (Underpowered: Loco max 5000, trailing tons = 30 + 5975 = 6005)
INSERT INTO train_consist VALUES (1, 'Q-CHILAA1', 1, 'LOCO', 'ENG-1', 'N', 0, 'NONE');
INSERT INTO train_consist VALUES (2, 'Q-CHILAA1', 2, 'CAR', 'CAR-101', 'Y', 5975, 'NONE');

-- Train 2 (Hazmat Violations: 4 violations total)
INSERT INTO train_consist VALUES (3, 'M-CHIGAL1', 1, 'LOCO', 'ENG-2', 'N', 0, 'NONE');
INSERT INTO train_consist VALUES (4, 'M-CHIGAL1', 2, 'CAR', 'CAR-102', 'Y', 50, 'UN1005'); -- Viol: Next to loco 1
INSERT INTO train_consist VALUES (5, 'M-CHIGAL1', 3, 'CAR', 'CAR-101', 'Y', 50, 'NONE');
INSERT INTO train_consist VALUES (6, 'M-CHIGAL1', 4, 'CAR', 'CAR-102', 'Y', 50, 'UN1203'); -- Viol: Next to loco 5
INSERT INTO train_consist VALUES (7, 'M-CHIGAL1', 5, 'LOCO', 'ENG-1', 'N', 0, 'NONE');
INSERT INTO train_consist VALUES (8, 'M-CHIGAL1', 6, 'CAR', 'CAR-102', 'Y', 50, 'UN1005'); -- Viol: Next to loco 5
INSERT INTO train_consist VALUES (9, 'M-CHIGAL1', 7, 'CAR', 'CAR-101', 'Y', 50, 'NONE');
INSERT INTO train_consist VALUES (10, 'M-CHIGAL1', 8, 'CAR', 'CAR-102', 'Y', 50, 'UN1203'); -- Viol: Next to loco 9
INSERT INTO train_consist VALUES (11, 'M-CHIGAL1', 9, 'LOCO', 'ENG-2', 'N', 0, 'NONE');

-- Train 3 (Overloaded cars: Total weights exceed 143)
INSERT INTO train_consist VALUES (12, 'U-COAL1', 1, 'LOCO', 'ENG-2', 'N', 0, 'NONE');
INSERT INTO train_consist VALUES (13, 'U-COAL1', 2, 'CAR', 'CAR-103', 'Y', 120, 'NONE'); -- 120 + 30 = 150 > 143
INSERT INTO train_consist VALUES (14, 'U-COAL1', 3, 'CAR', 'CAR-104', 'Y', 125, 'NONE'); -- 125 + 30 = 155 > 143
INSERT INTO train_consist VALUES (15, 'U-COAL1', 4, 'CAR', 'CAR-105', 'Y', 130, 'NONE'); -- 130 + 30 = 160 > 143

-- Train 4 (Underpowered 2: Loco max 5000, trailing tons = 5100 + 30 = 5130)
INSERT INTO train_consist VALUES (16, 'Z-NYCCHI1', 1, 'LOCO', 'ENG-1', 'N', 0, 'NONE');
INSERT INTO train_consist VALUES (17, 'Z-NYCCHI1', 2, 'CAR', 'CAR-101', 'Y', 5100, 'NONE');

COMMIT;
EXIT;
EOSQL

# 5. Pre-configure SQL Developer Connection
mkdir -p /home/ga/.sqldeveloper/system24.3.0.284.2209/o.jdeveloper.db.connection.24.2.0.284.2209
CONN_FILE="/home/ga/.sqldeveloper/system24.3.0.284.2209/o.jdeveloper.db.connection.24.2.0.284.2209/connections.json"

cat > "$CONN_FILE" << 'CONNEOF'
{
  "connections": [
    {
      "name": "Rail Operations",
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
        "ConnName": "Rail Operations",
        "serviceName": "XEPDB1",
        "user": "rail_admin",
        "password": "Railroad2024"
      }
    }
  ]
}
CONNEOF
chown -R ga:ga /home/ga/.sqldeveloper

# 6. Ensure export directory exists
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# 7. Finalize Setup
echo "Taking initial screenshot..."
sleep 2
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="