#!/bin/bash
# Setup script for Municipal Building Energy Emissions Audit task
echo "=== Setting up Building Energy Emissions Audit ==="

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
  EXECUTE IMMEDIATE 'DROP USER env_auditor CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Create ENV_AUDITOR schema
# ---------------------------------------------------------------
echo "Creating ENV_AUDITOR schema..."
oracle_query "CREATE USER env_auditor IDENTIFIED BY EnvAudit2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE PROCEDURE TO env_auditor;
EXIT;" "system"

# ---------------------------------------------------------------
# 4. Create Tables and Sequences
# ---------------------------------------------------------------
echo "Creating schema tables and sequences..."

sudo docker exec -i oracle-xe sqlplus -s env_auditor/EnvAudit2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE property_emission_limits (
    property_type        VARCHAR2(100) PRIMARY KEY,
    ghg_intensity_limit  NUMBER(10,5)  NOT NULL
);

CREATE TABLE buildings (
    bbl_id         NUMBER PRIMARY KEY,
    bin_number     VARCHAR2(20),
    owner_name     VARCHAR2(200),
    property_type  VARCHAR2(100) REFERENCES property_emission_limits(property_type),
    gross_sqft     NUMBER NOT NULL
);

CREATE SEQUENCE reading_seq START WITH 1000 INCREMENT BY 1;

CREATE TABLE meter_readings (
    reading_id    NUMBER PRIMARY KEY,
    bbl_id        NUMBER REFERENCES buildings(bbl_id),
    fuel_type     VARCHAR2(50) NOT NULL,
    usage_amount  NUMBER(15,2) NOT NULL,
    reading_date  DATE
);

CREATE SEQUENCE notice_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE emission_notices (
    notice_id         NUMBER PRIMARY KEY,
    bbl_id            NUMBER REFERENCES buildings(bbl_id),
    owner_name        VARCHAR2(200),
    exceedance_amount NUMBER(15,2),
    fine_amount       NUMBER(15,2),
    notice_date       DATE
);

EXIT;
EOSQL

# ---------------------------------------------------------------
# 5. Insert Realistic Sample Data
# ---------------------------------------------------------------
echo "Inserting regulatory limits and building data..."

sudo docker exec -i oracle-xe sqlplus -s env_auditor/EnvAudit2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- Insert Limits (metric tons CO2e per sqft)
INSERT INTO property_emission_limits VALUES ('Office', 0.00846);
INSERT INTO property_emission_limits VALUES ('Multifamily Housing', 0.00675);
INSERT INTO property_emission_limits VALUES ('Retail Store', 0.01181);
INSERT INTO property_emission_limits VALUES ('Hotel', 0.00987);

-- Insert Buildings
INSERT INTO buildings VALUES (100000001, '1001', 'Empire Realty', 'Office', 1500000);
INSERT INTO buildings VALUES (100000002, '1002', 'Downtown Residential', 'Multifamily Housing', 250000);
INSERT INTO buildings VALUES (100000003, '1003', 'MegaMart Group', 'Retail Store', 85000);
INSERT INTO buildings VALUES (100000004, '1004', 'Grand Hospitality LLC', 'Hotel', 320000);
INSERT INTO buildings VALUES (100000005, '1005', 'Green Tech Hub', 'Office', 450000);
INSERT INTO buildings VALUES (100000006, '1006', 'Luxury Condos Inc', 'Multifamily Housing', 120000);

-- Insert Meter Readings (2024 aggregates for simplicity in this dataset)
-- Building 1: Office, very high usage (Non-compliant)
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000001, 'Electricity', 25000000, TO_DATE('2024-12-31','YYYY-MM-DD'));
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000001, 'Natural Gas', 1500000, TO_DATE('2024-12-31','YYYY-MM-DD'));
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000001, 'District Steam', 50000, TO_DATE('2024-12-31','YYYY-MM-DD'));

-- Building 2: Multifamily, moderate usage (Compliant)
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000002, 'Electricity', 1200000, TO_DATE('2024-12-31','YYYY-MM-DD'));
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000002, 'Natural Gas', 80000, TO_DATE('2024-12-31','YYYY-MM-DD'));

-- Building 3: Retail, high electricity only (Non-compliant)
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000003, 'Electricity', 4500000, TO_DATE('2024-12-31','YYYY-MM-DD'));

-- Building 4: Hotel, mixed usage (Non-compliant)
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000004, 'Electricity', 8000000, TO_DATE('2024-12-31','YYYY-MM-DD'));
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000004, 'Natural Gas', 400000, TO_DATE('2024-12-31','YYYY-MM-DD'));

-- Building 5: Office, very efficient (Compliant)
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000005, 'Electricity', 2000000, TO_DATE('2024-12-31','YYYY-MM-DD'));
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000005, 'Natural Gas', 10000, TO_DATE('2024-12-31','YYYY-MM-DD'));

-- Building 6: Multifamily, electric and steam (Non-compliant)
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000006, 'Electricity', 900000, TO_DATE('2024-12-31','YYYY-MM-DD'));
INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 100000006, 'District Steam', 25000, TO_DATE('2024-12-31','YYYY-MM-DD'));

COMMIT;
EXIT;
EOSQL

echo "Data setup complete."

# ---------------------------------------------------------------
# 6. Pre-configure SQL Developer connection
# ---------------------------------------------------------------
echo "Configuring SQL Developer connection for ENV_AUDITOR..."
ensure_hr_connection "Environment Audit DB" "env_auditor" "EnvAudit2024"

# Open the connection in SQL Developer if running
open_hr_connection_in_sqldeveloper

# Take screenshot of initial state
take_screenshot /tmp/task_start_screenshot.png ga

echo "=== Task Setup Complete ==="