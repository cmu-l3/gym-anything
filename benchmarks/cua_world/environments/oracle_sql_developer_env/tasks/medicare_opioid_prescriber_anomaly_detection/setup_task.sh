#!/bin/bash
echo "=== Setting up Medicare Opioid Prescriber Anomaly Detection Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# Clean up
oracle_query "BEGIN EXECUTE IMMEDIATE 'DROP USER medicare_admin CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END; / EXIT;" "system" 2>/dev/null || true
sleep 2

# Create User
oracle_query "CREATE USER medicare_admin IDENTIFIED BY Medicare2024
  DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE TO medicare_admin;
GRANT CREATE VIEW, CREATE MATERIALIZED VIEW, CREATE TABLE, CREATE SESSION TO medicare_admin;
EXIT;" "system"

# Create Tables & Data
sudo docker exec -i oracle-xe sqlplus -s medicare_admin/Medicare2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE prescribers (
    npi NUMBER PRIMARY KEY,
    first_name VARCHAR2(100),
    last_name VARCHAR2(100),
    specialty VARCHAR2(100)
);

CREATE TABLE drugs (
    drug_id NUMBER PRIMARY KEY,
    brand_name VARCHAR2(100),
    generic_name VARCHAR2(100),
    strength_mg NUMBER,
    is_opioid VARCHAR2(1)
);

CREATE TABLE cdc_mme_factors (
    generic_name VARCHAR2(100) PRIMARY KEY,
    mme_factor NUMBER(10,2)
);

CREATE TABLE prescriptions_stg (
    prescription_id NUMBER PRIMARY KEY,
    npi NUMBER REFERENCES prescribers(npi),
    raw_drug_desc VARCHAR2(200),
    dispense_quarter VARCHAR2(10),
    total_qty NUMBER,
    day_supply NUMBER
);

CREATE SEQUENCE presc_seq START WITH 1 INCREMENT BY 1;

BEGIN
  -- Insert Master Data
  INSERT INTO drugs VALUES (1, 'OXYCONTIN', 'OXYCODONE HCL', 10, 'Y');
  INSERT INTO drugs VALUES (2, 'ROXICODONE', 'OXYCODONE HCL', 20, 'Y');
  INSERT INTO drugs VALUES (3, 'VICODIN', 'HYDROCODONE', 5, 'Y');
  INSERT INTO drugs VALUES (4, 'LIPITOR', 'ATORVASTATIN', 20, 'N');

  INSERT INTO cdc_mme_factors VALUES ('OXYCODONE HCL', 1.5);
  INSERT INTO cdc_mme_factors VALUES ('HYDROCODONE', 1.0);
  INSERT INTO cdc_mme_factors VALUES ('ATORVASTATIN', 0);

  -- Family Medicine Prescribers
  FOR i IN 1..50 LOOP
    INSERT INTO prescribers VALUES (1000+i, 'John'||i, 'Doe'||i, 'Family Medicine');
    
    IF i = 1 THEN -- STATISTICAL_OUTLIER
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 1000+i, '  OXYCODONE HCL 10MG ', '2023-Q1', 2000, 30);
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 1000+i, '  OXYCODONE HCL 10MG ', '2023-Q2', 2000, 30);
    ELSIF i = 2 THEN -- RAPID_ACCELERATION
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 1000+i, 'OxyContin 10mg', '2023-Q1', 100, 30);
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 1000+i, 'OxyContin 10mg', '2023-Q2', 400, 30);
    ELSIF i = 3 THEN -- CRITICAL_RISK
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 1000+i, 'OXYCODONE HCL 10MG', '2023-Q1', 1000, 30);
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 1000+i, 'OXYCODONE HCL 10MG', '2023-Q2', 3000, 30);
    ELSE
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 1000+i, 'OXYCODONE HCL 10MG', '2023-Q1', 100, 30);
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 1000+i, 'OXYCODONE HCL 10MG', '2023-Q2', 100, 30);
    END IF;
  END LOOP;

  -- Internal Medicine Prescribers
  FOR i IN 1..50 LOOP
    INSERT INTO prescribers VALUES (2000+i, 'Jane'||i, 'Smith'||i, 'Internal Medicine');
    
    IF i = 1 THEN -- STATISTICAL_OUTLIER
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 2000+i, '  OXYCODONE HCL 10MG ', '2023-Q1', 2000, 30);
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 2000+i, '  OXYCODONE HCL 10MG ', '2023-Q2', 2000, 30);
    ELSIF i = 2 THEN -- RAPID_ACCELERATION
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 2000+i, 'OxyContin 10mg', '2023-Q1', 100, 30);
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 2000+i, 'OxyContin 10mg', '2023-Q2', 400, 30);
    ELSIF i = 3 THEN -- CRITICAL_RISK
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 2000+i, 'OXYCODONE HCL 10MG', '2023-Q1', 1000, 30);
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 2000+i, 'OXYCODONE HCL 10MG', '2023-Q2', 3000, 30);
    ELSE
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 2000+i, 'OXYCODONE HCL 10MG', '2023-Q1', 100, 30);
      INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 2000+i, 'OXYCODONE HCL 10MG', '2023-Q2', 100, 30);
    END IF;
  END LOOP;

  -- Add some unmatchable garbage records to test cleansing
  INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 1010, 'UNKNOWN PILL 50MG', '2023-Q1', 50, 15);
  INSERT INTO prescriptions_stg VALUES (presc_seq.NEXTVAL, 2010, 'FAKE DRUG', '2023-Q2', 20, 10);
  
  COMMIT;
END;
/
EXIT;
EOSQL

echo "Data setup complete."

# Pre-configure SQL Developer Connection
ensure_hr_connection "Medicare DB" "medicare_admin" "Medicare2024"
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="