#!/bin/bash
# Setup script for Health Registry Record Linkage
echo "=== Setting up Health Registry Record Linkage ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# 1. Clean up previous run artifacts
echo "Cleaning up previous schemas..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER hie_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" "OraclePassword123" 2>/dev/null || true

sleep 2

# 2. Create hie_admin schema
echo "Creating HIE_ADMIN schema..."
oracle_query "CREATE USER hie_admin IDENTIFIED BY Health2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE SEQUENCE, CREATE TABLE, CREATE SESSION TO hie_admin;
EXIT;" "system" "OraclePassword123"

# 3. Create tables and populate realistic synthetic data
echo "Populating patient data..."
sudo docker exec -i oracle-xe sqlplus -s hie_admin/Health2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE CLINIC_A_PATIENTS (
    pat_id VARCHAR2(20) PRIMARY KEY,
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    date_of_birth DATE,
    gender VARCHAR2(1),
    ssn VARCHAR2(9)
);

CREATE TABLE CLINIC_B_PATIENTS (
    pat_id VARCHAR2(20) PRIMARY KEY,
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    date_of_birth DATE,
    gender VARCHAR2(1),
    ssn VARCHAR2(9)
);

-- Generate Data
BEGIN
  FOR i IN 1..100 LOOP
    IF i <= 45 THEN
      -- Create 45 matching records with typos (different IDs, slightly modified names and SSNs)
      -- Jaro-Winkler for JONATHAN vs JONATHON is ~92 (>= 85 threshold)
      -- Jaro-Winkler for SMITH vs SMYTH is 88 (>= 85 threshold)
      -- SSN edit distance is exactly 1 (<= 2 threshold)
      -- DOB and Gender remain identical to serve as blocking keys
      INSERT INTO CLINIC_A_PATIENTS VALUES ('A'||i, 'JONATHAN'||i, 'SMITH', DATE '1980-01-01' + i, 'M', '123456' || LPAD(i, 3, '0'));
      INSERT INTO CLINIC_B_PATIENTS VALUES ('B'||i, 'JONATHON'||i, 'SMYTH', DATE '1980-01-01' + i, 'M', '123457' || LPAD(i, 3, '0'));
    ELSE
      -- Create 55 non-matching records (completely different names/DOB to prevent false positives)
      INSERT INTO CLINIC_A_PATIENTS VALUES ('A'||i, 'MICHAEL'||i, 'JOHNSON', DATE '1990-01-01' + i, 'M', '223456' || LPAD(i, 3, '0'));
      INSERT INTO CLINIC_B_PATIENTS VALUES ('B'||i, 'SARAH'||i, 'WILLIAMS', DATE '1995-01-01' + i, 'F', '323456' || LPAD(i, 3, '0'));
    END IF;
  END LOOP;
  COMMIT;
END;
/
EXIT;
EOSQL

# 4. Create SQL Developer Connection Profile
echo "Configuring SQL Developer connection..."
mkdir -p /home/ga/.sqldeveloper/system24.3.0/o.jdeveloper.db.connection.24.2.0.284.2209
cat > /home/ga/.sqldeveloper/system24.3.0/o.jdeveloper.db.connection.24.2.0.284.2209/connections.json << 'CONNEOF'
{
  "connections": [
    {
      "name": "HIE Admin Database",
      "type": "jdbc",
      "info": {
        "SavePassword": "true",
        "OracleConnectionType": "BASIC",
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "hostname": "localhost",
        "driver": "oracle.jdbc.OracleDriver",
        "port": "1521",
        "subtype": "oraJDBC",
        "ConnName": "HIE Admin Database",
        "serviceName": "XEPDB1",
        "user": "hie_admin",
        "password": "Health2024"
      }
    }
  ]
}
CONNEOF
chown -R ga:ga /home/ga/.sqldeveloper

# 5. Ensure SQL Developer is visible and ready
echo "Focusing SQL Developer..."
su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &" > /dev/null 2>&1
sleep 15
DISPLAY=:1 wmctrl -r "Oracle SQL Developer" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Pre-create exports directory
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="