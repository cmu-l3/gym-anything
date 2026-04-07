#!/bin/bash
# Setup script for Bill of Materials Cost Rollup and Explosion Analysis task
echo "=== Setting up BOM Cost Rollup and Explosion Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# 1. Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# 2. Clean up previous run artifacts
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER mfg_engineer CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# 3. Create MFG_ENGINEER schema
echo "Creating MFG_ENGINEER user..."
oracle_query "CREATE USER mfg_engineer IDENTIFIED BY Mfg2024
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS;

GRANT CONNECT, RESOURCE TO mfg_engineer;
GRANT CREATE VIEW TO mfg_engineer;
GRANT CREATE MATERIALIZED VIEW TO mfg_engineer;
GRANT CREATE PROCEDURE TO mfg_engineer;
GRANT CREATE SESSION TO mfg_engineer;
GRANT CREATE TABLE TO mfg_engineer;
GRANT CREATE SEQUENCE TO mfg_engineer;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create mfg_engineer user"
    exit 1
fi
echo "mfg_engineer user created."

# 4. Create Tables and Plant Circular References
echo "Creating BOM tables and inserting data..."
sudo docker exec -i oracle-xe sqlplus -s mfg_engineer/Mfg2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE items (
    item_id       NUMBER PRIMARY KEY,
    item_number   VARCHAR2(50) UNIQUE NOT NULL,
    item_type     VARCHAR2(30) NOT NULL,
    category      VARCHAR2(50),
    description   VARCHAR2(200)
);

CREATE TABLE bom_headers (
    bom_id        NUMBER PRIMARY KEY,
    item_id       NUMBER REFERENCES items(item_id),
    revision      VARCHAR2(10),
    is_active     NUMBER(1) DEFAULT 1
);

CREATE TABLE bom_lines (
    line_id           NUMBER PRIMARY KEY,
    bom_id            NUMBER REFERENCES bom_headers(bom_id),
    parent_item_id    NUMBER REFERENCES items(item_id),
    component_item_id NUMBER REFERENCES items(item_id),
    quantity_per      NUMBER(10,4) NOT NULL
);

-- Insert Items
INSERT INTO items VALUES (1, 'WS-5000', 'FINISHED_GOOD', 'Audio', 'Wireless Speaker System');
INSERT INTO items VALUES (2, 'PCB-AMP-01', 'SUB_ASSEMBLY', 'PCBs', 'Amplifier Board');
INSERT INTO items VALUES (3, 'ENC-WS-01', 'SUB_ASSEMBLY', 'Enclosures', 'Main Plastic Enclosure');
INSERT INTO items VALUES (4, 'BATT-MOD', 'SUB_ASSEMBLY', 'Power', 'Battery Module');
INSERT INTO items VALUES (10, 'CON-2PIN', 'COMPONENT', 'Connectors', '2-Pin Header');
INSERT INTO items VALUES (11, 'PLAS-ABS-BLK', 'RAW_MATERIAL', 'Plastics', 'ABS Plastic Black');
INSERT INTO items VALUES (12, 'SCREW-M3', 'COMPONENT', 'Hardware', 'M3 10mm Screw');
INSERT INTO items VALUES (13, 'CABLE-AWG20', 'RAW_MATERIAL', 'Cables', '20 AWG Wire');
INSERT INTO items VALUES (14, 'IC-TPA3116', 'COMPONENT', 'ICs', 'Class D Amp IC');
INSERT INTO items VALUES (15, 'SPK-DRV-4IN', 'COMPONENT', 'Audio', '4-inch Speaker Driver');
INSERT INTO items VALUES (16, 'PKG-BOX-WS', 'RAW_MATERIAL', 'Packaging', 'Retail Box WS-5000');

-- Insert BOM Headers
INSERT INTO bom_headers VALUES (100, 1, 'A', 1);
INSERT INTO bom_headers VALUES (101, 2, 'B', 1);
INSERT INTO bom_headers VALUES (102, 3, 'A', 1);
INSERT INTO bom_headers VALUES (103, 4, 'C', 1);

-- Insert Valid BOM Lines
-- WS-5000 structure
INSERT INTO bom_lines VALUES (1000, 100, 1, 2, 1);    -- 1 Amp Board
INSERT INTO bom_lines VALUES (1001, 100, 1, 3, 1);    -- 1 Enclosure
INSERT INTO bom_lines VALUES (1002, 100, 1, 4, 1);    -- 1 Battery Module
INSERT INTO bom_lines VALUES (1003, 100, 1, 15, 2);   -- 2 Speaker Drivers
INSERT INTO bom_lines VALUES (1004, 100, 1, 16, 1);   -- 1 Retail Box

-- PCB-AMP-01 structure
INSERT INTO bom_lines VALUES (1005, 101, 2, 14, 1);   -- 1 Amp IC
INSERT INTO bom_lines VALUES (1006, 101, 2, 10, 4);   -- 4 Connectors

-- ENC-WS-01 structure
INSERT INTO bom_lines VALUES (1007, 102, 3, 11, 0.5); -- 0.5 kg ABS
INSERT INTO bom_lines VALUES (1008, 102, 3, 12, 8);   -- 8 Screws

-- BATT-MOD structure
INSERT INTO bom_lines VALUES (1009, 103, 4, 13, 0.2); -- 0.2m Cable

-- ======================================================================
-- PLANT CIRCULAR REFERENCES (ERRORS TO BE FIXED BY AGENT)
-- ======================================================================
-- Cycle 1: PCB-AMP-01 (2) -> CON-2PIN (10) -> PCB-AMP-01 (2)
INSERT INTO bom_lines VALUES (9991, 101, 10, 2, 1); 

-- Cycle 2: ENC-WS-01 (3) -> SCREW-M3 (12) -> PLAS-ABS-BLK (11) -> ENC-WS-01 (3)
INSERT INTO bom_lines VALUES (9992, 102, 12, 11, 1);
INSERT INTO bom_lines VALUES (9993, 102, 11, 3, 1);

-- Cycle 3: BATT-MOD (4) -> CABLE-AWG20 (13) -> BATT-MOD (4)
INSERT INTO bom_lines VALUES (9994, 103, 13, 4, 1);

COMMIT;
EXIT;
EOSQL

# 5. Pre-configure SQL Developer connection for MFG_ENGINEER
ensure_mfg_connection() {
    local SQLDEVELOPER_SYSTEM_DIR=$(find /home/ga/.sqldeveloper -maxdepth 1 -name "system*" -type d 2>/dev/null | head -1)
    if [ -n "$SQLDEVELOPER_SYSTEM_DIR" ]; then
        local CONN_DIR=$(find "$SQLDEVELOPER_SYSTEM_DIR" -name "o.jdeveloper.db.connection*" -type d 2>/dev/null | head -1)
        if [ -z "$CONN_DIR" ]; then
            CONN_DIR="$SQLDEVELOPER_SYSTEM_DIR/o.jdeveloper.db.connection.24.2.0.284.2209"
            mkdir -p "$CONN_DIR"
        fi
        local CONN_FILE="$CONN_DIR/connections.json"
        
        # Rewrite connections.json to include mfg_engineer
        cat > "$CONN_FILE" << CONNEOF
{
  "connections": [
    {
      "name": "Manufacturing BOM",
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
        "ConnName": "Manufacturing BOM",
        "serviceName": "XEPDB1",
        "user": "mfg_engineer",
        "password": "Mfg2024"
      }
    }
  ]
}
CONNEOF
        chown ga:ga "$CONN_FILE"
    fi
}
ensure_mfg_connection

# 6. Take initial screenshot showing environment setup complete
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="