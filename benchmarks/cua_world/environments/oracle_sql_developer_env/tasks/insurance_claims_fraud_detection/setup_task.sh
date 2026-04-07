#!/bin/bash
# Setup script for Insurance Claims Fraud Detection task
echo "=== Setting up Insurance Claims Fraud Detection ==="

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

# --- Drop and recreate the CLAIMS_ANALYST user cleanly ---
echo "Setting up CLAIMS schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER claims_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER claims_analyst IDENTIFIED BY Claims2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO claims_analyst;
GRANT RESOURCE TO claims_analyst;
GRANT CREATE VIEW TO claims_analyst;
GRANT CREATE MATERIALIZED VIEW TO claims_analyst;
GRANT CREATE PROCEDURE TO claims_analyst;
GRANT CREATE SESSION TO claims_analyst;
GRANT CREATE TYPE TO claims_analyst;
GRANT CREATE TABLE TO claims_analyst;
EXIT;" "system"

echo "CLAIMS_ANALYST user created with required privileges"

# ============================================================
# CREATE TABLES
# ============================================================
echo "Creating PROVIDERS table..."
oracle_query "CREATE TABLE providers (
  provider_id     NUMBER PRIMARY KEY,
  provider_name   VARCHAR2(200) NOT NULL,
  npi_number      VARCHAR2(10) NOT NULL,
  specialty       VARCHAR2(100),
  state           VARCHAR2(2),
  city            VARCHAR2(100),
  zip_code        VARCHAR2(10),
  enrollment_date DATE
);
EXIT;" "claims_analyst" "Claims2024"

echo "Creating PATIENTS table..."
oracle_query "CREATE TABLE patients (
  patient_id      NUMBER PRIMARY KEY,
  patient_name    VARCHAR2(200) NOT NULL,
  date_of_birth   DATE,
  gender          VARCHAR2(1),
  zip_code        VARCHAR2(10),
  insurance_plan  VARCHAR2(50),
  enrollment_date DATE
);
EXIT;" "claims_analyst" "Claims2024"

echo "Creating PROCEDURE_CODES table..."
oracle_query "CREATE TABLE procedure_codes (
  procedure_code   VARCHAR2(10) PRIMARY KEY,
  description      VARCHAR2(500),
  category         VARCHAR2(100),
  base_rate        NUMBER(10,2),
  modifier_allowed NUMBER(1) DEFAULT 1
);
EXIT;" "claims_analyst" "Claims2024"

echo "Creating CLAIMS table..."
oracle_query "CREATE TABLE claims (
  claim_id         NUMBER PRIMARY KEY,
  provider_id      NUMBER REFERENCES providers(provider_id),
  patient_id       NUMBER REFERENCES patients(patient_id),
  procedure_code   VARCHAR2(10) REFERENCES procedure_codes(procedure_code),
  claim_date       DATE,
  service_date     DATE,
  amount           NUMBER(12,2),
  units            NUMBER DEFAULT 1,
  diagnosis_code   VARCHAR2(10),
  claim_status     VARCHAR2(20) DEFAULT 'PENDING',
  adjudication_date DATE,
  paid_amount      NUMBER(12,2)
);
EXIT;" "claims_analyst" "Claims2024"

echo "FRAUD_FLAGS table will be created by the agent as part of the task"

# ============================================================
# CREATE SEQUENCES
# ============================================================
echo "Creating sequences..."
oracle_query "CREATE SEQUENCE claim_seq START WITH 1000 INCREMENT BY 1;
CREATE SEQUENCE flag_seq START WITH 1 INCREMENT BY 1;
EXIT;" "claims_analyst" "Claims2024"

# ============================================================
# INSERT PROCEDURE CODES (CMS HCPCS)
# ============================================================
echo "Inserting procedure codes..."
oracle_query "INSERT INTO procedure_codes VALUES ('99213', 'Office visit, established patient, level 3', 'E&M Office', 92.00, 1);
INSERT INTO procedure_codes VALUES ('99214', 'Office visit, established patient, level 4', 'E&M Office', 130.00, 1);
INSERT INTO procedure_codes VALUES ('99215', 'Office visit, established patient, level 5', 'E&M Office', 175.00, 1);
INSERT INTO procedure_codes VALUES ('99203', 'Office visit, new patient, level 3', 'E&M Office', 110.00, 1);
INSERT INTO procedure_codes VALUES ('99204', 'Office visit, new patient, level 4', 'E&M Office', 167.00, 1);
INSERT INTO procedure_codes VALUES ('99205', 'Office visit, new patient, level 5', 'E&M Office', 211.00, 1);
INSERT INTO procedure_codes VALUES ('99281', 'ER visit, level 1', 'E&M Emergency', 55.00, 1);
INSERT INTO procedure_codes VALUES ('99282', 'ER visit, level 2', 'E&M Emergency', 95.00, 1);
INSERT INTO procedure_codes VALUES ('99283', 'ER visit, level 3', 'E&M Emergency', 145.00, 1);
INSERT INTO procedure_codes VALUES ('99284', 'ER visit, level 4', 'E&M Emergency', 250.00, 1);
INSERT INTO procedure_codes VALUES ('99285', 'ER visit, level 5', 'E&M Emergency', 400.00, 1);
INSERT INTO procedure_codes VALUES ('90837', 'Psychotherapy, 60 min', 'Mental Health', 130.00, 1);
INSERT INTO procedure_codes VALUES ('90834', 'Psychotherapy, 45 min', 'Mental Health', 100.00, 1);
INSERT INTO procedure_codes VALUES ('27447', 'Total knee replacement', 'Surgery', 1450.00, 1);
INSERT INTO procedure_codes VALUES ('27130', 'Total hip replacement', 'Surgery', 1400.00, 1);
INSERT INTO procedure_codes VALUES ('43239', 'Upper GI endoscopy with biopsy', 'Diagnostic', 350.00, 1);
INSERT INTO procedure_codes VALUES ('45380', 'Colonoscopy with biopsy', 'Diagnostic', 400.00, 1);
INSERT INTO procedure_codes VALUES ('70553', 'Brain MRI without/with contrast', 'Imaging', 500.00, 1);
INSERT INTO procedure_codes VALUES ('71260', 'CT chest with contrast', 'Imaging', 300.00, 1);
INSERT INTO procedure_codes VALUES ('93000', 'Electrocardiogram', 'Cardiology', 25.00, 1);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# ============================================================
# INSERT PROVIDERS (20 providers)
# ============================================================
echo "Inserting providers..."
oracle_query "INSERT INTO providers VALUES (1, 'Dr. James Wilson', '1234567890', 'Family Medicine', 'NY', 'New York', '10001', DATE '2015-03-15');
INSERT INTO providers VALUES (2, 'Dr. Sarah Chen', '1234567891', 'Internal Medicine', 'CA', 'Los Angeles', '90001', DATE '2016-07-22');
INSERT INTO providers VALUES (3, 'Dr. Michael Torres', '1234567892', 'Family Medicine', 'TX', 'Houston', '77001', DATE '2014-11-08');
INSERT INTO providers VALUES (4, 'Dr. Emily Johnson', '1234567893', 'Orthopedics', 'FL', 'Miami', '33101', DATE '2017-01-30');
INSERT INTO providers VALUES (5, 'Dr. Robert Kim', '1234567894', 'Internal Medicine', 'IL', 'Chicago', '60601', DATE '2013-09-14');
INSERT INTO providers VALUES (6, 'Dr. Lisa Patel', '1234567895', 'Psychiatry', 'PA', 'Philadelphia', '19101', DATE '2018-04-20');
INSERT INTO providers VALUES (7, 'Dr. David Martinez', '1234567896', 'Emergency Medicine', 'OH', 'Columbus', '43201', DATE '2015-06-11');
INSERT INTO providers VALUES (8, 'Dr. Jennifer Brown', '1234567897', 'Radiology', 'NY', 'Buffalo', '14201', DATE '2016-12-03');
INSERT INTO providers VALUES (9, 'Dr. William Lee', '1234567898', 'Gastroenterology', 'CA', 'San Francisco', '94101', DATE '2017-08-25');
INSERT INTO providers VALUES (10, 'Dr. Amanda Garcia', '1234567899', 'Family Medicine', 'TX', 'Dallas', '75201', DATE '2019-02-17');
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

oracle_query "INSERT INTO providers VALUES (11, 'Dr. Christopher Davis', '1234567900', 'Internal Medicine', 'FL', 'Tampa', '33601', DATE '2014-05-09');
INSERT INTO providers VALUES (12, 'Dr. Michelle Wong', '1234567901', 'Family Medicine', 'IL', 'Springfield', '62701', DATE '2016-10-28');
INSERT INTO providers VALUES (13, 'Dr. Richard Thompson', '1234567902', 'Internal Medicine', 'PA', 'Pittsburgh', '15201', DATE '2015-01-16');
INSERT INTO providers VALUES (14, 'Dr. Stephanie Clark', '1234567903', 'Cardiology', 'OH', 'Cleveland', '44101', DATE '2018-07-04');
INSERT INTO providers VALUES (15, 'Dr. Daniel Harris', '1234567904', 'Internal Medicine', 'NY', 'Rochester', '14601', DATE '2013-03-22');
INSERT INTO providers VALUES (16, 'Dr. Karen Mitchell', '1234567905', 'Family Medicine', 'CA', 'San Diego', '92101', DATE '2017-11-15');
INSERT INTO providers VALUES (17, 'Dr. Thomas Anderson', '1234567906', 'Internal Medicine', 'TX', 'Austin', '78701', DATE '2016-06-30');
INSERT INTO providers VALUES (18, 'Dr. Nicole Robinson', '1234567907', 'Family Medicine', 'FL', 'Orlando', '32801', DATE '2019-09-12');
INSERT INTO providers VALUES (19, 'Dr. Mark Sullivan', '1234567908', 'Internal Medicine', 'IL', 'Naperville', '60540', DATE '2020-01-08');
INSERT INTO providers VALUES (20, 'Dr. Rachel Foster', '1234567909', 'Family Medicine', 'PA', 'Harrisburg', '17101', DATE '2018-04-25');
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# ============================================================
# INSERT PATIENTS (50 patients)
# ============================================================
echo "Inserting patients (batch 1 of 3)..."
oracle_query "INSERT INTO patients VALUES (1, 'John Smith', DATE '1955-03-12', 'M', '10002', 'Medicare Part B', DATE '2020-01-15');
INSERT INTO patients VALUES (2, 'Mary Johnson', DATE '1948-07-23', 'F', '90002', 'Medicare Part B', DATE '2019-06-20');
INSERT INTO patients VALUES (3, 'Robert Williams', DATE '1962-11-05', 'M', '77002', 'Commercial PPO', DATE '2021-03-10');
INSERT INTO patients VALUES (4, 'Patricia Brown', DATE '1970-04-18', 'F', '33102', 'Commercial HMO', DATE '2020-08-05');
INSERT INTO patients VALUES (5, 'James Davis', DATE '1945-09-30', 'M', '60602', 'Medicare Advantage', DATE '2018-11-22');
INSERT INTO patients VALUES (6, 'Linda Miller', DATE '1958-01-14', 'F', '19102', 'Medicare Part B', DATE '2019-04-18');
INSERT INTO patients VALUES (7, 'Michael Wilson', DATE '1980-06-27', 'M', '43202', 'Commercial PPO', DATE '2022-01-09');
INSERT INTO patients VALUES (8, 'Elizabeth Moore', DATE '1973-12-08', 'F', '14202', 'Commercial HMO', DATE '2021-07-14');
INSERT INTO patients VALUES (9, 'David Taylor', DATE '1940-08-21', 'M', '94102', 'Medicare Advantage', DATE '2017-09-30');
INSERT INTO patients VALUES (10, 'Barbara Anderson', DATE '1965-02-03', 'F', '75202', 'Medicaid', DATE '2020-12-01');
INSERT INTO patients VALUES (11, 'Richard Thomas', DATE '1952-05-16', 'M', '33602', 'Medicare Part B', DATE '2019-03-25');
INSERT INTO patients VALUES (12, 'Susan Jackson', DATE '1978-10-29', 'F', '62702', 'Commercial PPO', DATE '2021-06-11');
INSERT INTO patients VALUES (13, 'Joseph White', DATE '1943-03-07', 'M', '15202', 'Medicare Advantage', DATE '2018-08-16');
INSERT INTO patients VALUES (14, 'Jessica Harris', DATE '1985-07-20', 'F', '44102', 'Commercial HMO', DATE '2022-04-03');
INSERT INTO patients VALUES (15, 'Thomas Martin', DATE '1960-12-11', 'M', '14602', 'Medicare Part B', DATE '2019-10-29');
INSERT INTO patients VALUES (16, 'Sarah Garcia', DATE '1975-08-04', 'F', '92102', 'Medicaid', DATE '2020-05-17');
INSERT INTO patients VALUES (17, 'Charles Robinson', DATE '1950-01-26', 'M', '78702', 'Medicare Advantage', DATE '2018-02-14');
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting patients (batch 2 of 3)..."
oracle_query "INSERT INTO patients VALUES (18, 'Karen Clark', DATE '1968-06-13', 'F', '32802', 'Commercial PPO', DATE '2021-09-08');
INSERT INTO patients VALUES (19, 'Daniel Lewis', DATE '1957-04-08', 'M', '60541', 'Medicare Part B', DATE '2019-07-21');
INSERT INTO patients VALUES (20, 'Nancy Walker', DATE '1982-09-19', 'F', '17102', 'Commercial HMO', DATE '2022-02-28');
INSERT INTO patients VALUES (21, 'Mark Hall', DATE '1947-11-25', 'M', '10003', 'Medicare Advantage', DATE '2017-12-10');
INSERT INTO patients VALUES (22, 'Betty Allen', DATE '1972-03-16', 'F', '90003', 'Commercial PPO', DATE '2020-04-22');
INSERT INTO patients VALUES (23, 'Steven Young', DATE '1964-08-01', 'M', '77003', 'Medicaid', DATE '2021-01-15');
INSERT INTO patients VALUES (24, 'Dorothy King', DATE '1939-12-30', 'F', '33103', 'Medicare Part B', DATE '2018-06-07');
INSERT INTO patients VALUES (25, 'Paul Wright', DATE '1976-05-22', 'M', '60603', 'Commercial HMO', DATE '2020-09-13');
INSERT INTO patients VALUES (26, 'Margaret Lopez', DATE '1953-02-09', 'F', '19103', 'Medicare Advantage', DATE '2019-01-28');
INSERT INTO patients VALUES (27, 'Andrew Hill', DATE '1988-07-14', 'M', '43203', 'Commercial PPO', DATE '2022-05-19');
INSERT INTO patients VALUES (28, 'Ruth Scott', DATE '1946-10-03', 'F', '14203', 'Medicare Part B', DATE '2018-03-16');
INSERT INTO patients VALUES (29, 'Joshua Green', DATE '1971-01-27', 'M', '94103', 'Medicaid', DATE '2020-07-04');
INSERT INTO patients VALUES (30, 'Virginia Adams', DATE '1959-06-18', 'F', '75203', 'Medicare Part B', DATE '2019-11-09');
INSERT INTO patients VALUES (31, 'Kenneth Baker', DATE '1944-04-12', 'M', '33603', 'Medicare Advantage', DATE '2017-08-23');
INSERT INTO patients VALUES (32, 'Helen Gonzalez', DATE '1983-09-05', 'F', '62703', 'Commercial PPO', DATE '2021-12-31');
INSERT INTO patients VALUES (33, 'George Nelson', DATE '1956-11-20', 'M', '15203', 'Medicare Part B', DATE '2019-05-14');
INSERT INTO patients VALUES (34, 'Deborah Carter', DATE '1969-03-28', 'F', '44103', 'Commercial HMO', DATE '2020-10-26');
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting patients (batch 3 of 3)..."
oracle_query "INSERT INTO patients VALUES (35, 'Edward Mitchell', DATE '1951-07-09', 'M', '14603', 'Medicare Advantage', DATE '2018-09-03');
INSERT INTO patients VALUES (36, 'Sharon Perez', DATE '1977-12-15', 'F', '92103', 'Medicaid', DATE '2021-04-17');
INSERT INTO patients VALUES (37, 'Ronald Roberts', DATE '1963-05-31', 'M', '78703', 'Commercial PPO', DATE '2020-02-09');
INSERT INTO patients VALUES (38, 'Laura Turner', DATE '1941-08-24', 'F', '32803', 'Medicare Part B', DATE '2017-11-28');
INSERT INTO patients VALUES (39, 'Jeffrey Phillips', DATE '1974-02-06', 'M', '60542', 'Commercial HMO', DATE '2021-08-12');
INSERT INTO patients VALUES (40, 'Carolyn Campbell', DATE '1986-10-17', 'F', '17103', 'Commercial PPO', DATE '2022-06-25');
INSERT INTO patients VALUES (41, 'Frank Parker', DATE '1949-06-29', 'M', '10004', 'Medicare Part B', DATE '2018-04-11');
INSERT INTO patients VALUES (42, 'Diane Evans', DATE '1967-01-11', 'F', '90004', 'Medicare Advantage', DATE '2019-12-06');
INSERT INTO patients VALUES (43, 'Gregory Edwards', DATE '1954-04-23', 'M', '77004', 'Medicare Part B', DATE '2018-07-19');
INSERT INTO patients VALUES (44, 'Marie Collins', DATE '1979-09-08', 'F', '33104', 'Commercial HMO', DATE '2021-02-22');
INSERT INTO patients VALUES (45, 'Raymond Stewart', DATE '1942-12-14', 'M', '60604', 'Medicare Advantage', DATE '2017-10-05');
INSERT INTO patients VALUES (46, 'Janet Sanchez', DATE '1966-03-26', 'F', '19104', 'Medicaid', DATE '2020-06-18');
INSERT INTO patients VALUES (47, 'Henry Morris', DATE '1961-08-07', 'M', '43204', 'Medicare Part B', DATE '2019-02-27');
INSERT INTO patients VALUES (48, 'Alice Rogers', DATE '1984-11-19', 'F', '14204', 'Commercial PPO', DATE '2022-03-14');
INSERT INTO patients VALUES (49, 'Walter Reed', DATE '1938-05-02', 'M', '94104', 'Medicare Advantage', DATE '2017-06-30');
INSERT INTO patients VALUES (50, 'Julie Cook', DATE '1973-07-21', 'F', '75204', 'Commercial PPO', DATE '2021-10-08');
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# ============================================================
# INSERT CLAIMS - LEGITIMATE (~220 claims)
# ============================================================
# These claims use realistic amounts near base rates (±15%)
# Natural Benford's Law distribution: many amounts start with 1 ($92->9, $130->1, $175->1, $110->1, $167->1, $25->2, $100->1, etc.)
# Weighted toward 99213 ($92) and 99214 ($130) for office visits

echo "Inserting legitimate claims (batch 1 of 7)..."
oracle_query "INSERT INTO claims (claim_id, provider_id, patient_id, procedure_code, claim_date, service_date, amount, units, diagnosis_code, claim_status, adjudication_date, paid_amount) VALUES (1, 1, 1, '99213', DATE '2024-01-05', DATE '2024-01-03', 88.50, 1, 'J06.9', 'PAID', DATE '2024-01-20', 88.50);
INSERT INTO claims VALUES (2, 1, 2, '99213', DATE '2024-01-08', DATE '2024-01-05', 95.00, 1, 'J20.9', 'PAID', DATE '2024-01-22', 95.00);
INSERT INTO claims VALUES (3, 1, 5, '99214', DATE '2024-01-10', DATE '2024-01-08', 125.00, 1, 'E11.9', 'PAID', DATE '2024-01-25', 125.00);
INSERT INTO claims VALUES (4, 1, 9, '99214', DATE '2024-01-15', DATE '2024-01-12', 135.00, 1, 'I10', 'PAID', DATE '2024-01-30', 135.00);
INSERT INTO claims VALUES (5, 1, 11, '99213', DATE '2024-01-22', DATE '2024-01-19', 90.00, 1, 'M54.5', 'PAID', DATE '2024-02-05', 90.00);
INSERT INTO claims VALUES (6, 2, 3, '99214', DATE '2024-01-12', DATE '2024-01-10', 128.00, 1, 'E11.65', 'PAID', DATE '2024-01-27', 128.00);
INSERT INTO claims VALUES (7, 2, 7, '99213', DATE '2024-01-18', DATE '2024-01-16', 94.00, 1, 'J02.9', 'PAID', DATE '2024-02-01', 94.00);
INSERT INTO claims VALUES (8, 2, 12, '99214', DATE '2024-01-25', DATE '2024-01-23', 132.00, 1, 'I10', 'PAID', DATE '2024-02-08', 132.00);
INSERT INTO claims VALUES (9, 2, 15, '99213', DATE '2024-02-02', DATE '2024-01-31', 89.50, 1, 'R05.9', 'PAID', DATE '2024-02-16', 89.50);
INSERT INTO claims VALUES (10, 2, 18, '99215', DATE '2024-02-08', DATE '2024-02-06', 170.00, 1, 'E78.5', 'PAID', DATE '2024-02-22', 170.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting legitimate claims (batch 2 of 7)..."
oracle_query "INSERT INTO claims VALUES (11, 3, 4, '99213', DATE '2024-02-05', DATE '2024-02-02', 96.00, 1, 'J06.9', 'PAID', DATE '2024-02-19', 96.00);
INSERT INTO claims VALUES (12, 3, 8, '99214', DATE '2024-02-12', DATE '2024-02-09', 126.00, 1, 'E11.9', 'PAID', DATE '2024-02-26', 126.00);
INSERT INTO claims VALUES (13, 3, 14, '99213', DATE '2024-02-19', DATE '2024-02-16', 92.00, 1, 'N39.0', 'PAID', DATE '2024-03-04', 92.00);
INSERT INTO claims VALUES (14, 3, 20, '99214', DATE '2024-02-26', DATE '2024-02-23', 138.00, 1, 'M79.3', 'PAID', DATE '2024-03-11', 138.00);
INSERT INTO claims VALUES (15, 3, 22, '99213', DATE '2024-03-04', DATE '2024-03-01', 85.00, 1, 'J02.9', 'PAID', DATE '2024-03-18', 85.00);
INSERT INTO claims VALUES (16, 3, 25, '99214', DATE '2024-03-11', DATE '2024-03-08', 140.00, 1, 'I10', 'PAID', DATE '2024-03-25', 140.00);
INSERT INTO claims VALUES (17, 4, 1, '27447', DATE '2024-03-05', DATE '2024-02-28', 1520.00, 1, 'M17.11', 'PAID', DATE '2024-03-20', 1520.00);
INSERT INTO claims VALUES (18, 4, 9, '27130', DATE '2024-04-10', DATE '2024-04-05', 1380.00, 1, 'M16.11', 'PAID', DATE '2024-04-25', 1380.00);
INSERT INTO claims VALUES (19, 4, 21, '27447', DATE '2024-05-15', DATE '2024-05-10', 1490.00, 1, 'M17.12', 'PAID', DATE '2024-05-30', 1490.00);
INSERT INTO claims VALUES (20, 4, 31, '27130', DATE '2024-06-20', DATE '2024-06-14', 1430.00, 1, 'M16.12', 'PAID', DATE '2024-07-05', 1430.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting legitimate claims (batch 3 of 7)..."
oracle_query "INSERT INTO claims VALUES (21, 5, 6, '99213', DATE '2024-02-15', DATE '2024-02-13', 93.00, 1, 'J06.9', 'PAID', DATE '2024-03-01', 93.00);
INSERT INTO claims VALUES (22, 5, 10, '99214', DATE '2024-02-22', DATE '2024-02-20', 134.00, 1, 'E11.9', 'PAID', DATE '2024-03-07', 134.00);
INSERT INTO claims VALUES (23, 5, 16, '99213', DATE '2024-03-01', DATE '2024-02-28', 91.00, 1, 'R10.9', 'PAID', DATE '2024-03-15', 91.00);
INSERT INTO claims VALUES (24, 5, 19, '99214', DATE '2024-03-08', DATE '2024-03-06', 129.00, 1, 'I10', 'PAID', DATE '2024-03-22', 129.00);
INSERT INTO claims VALUES (25, 5, 23, '99213', DATE '2024-03-15', DATE '2024-03-13', 97.00, 1, 'J20.9', 'PAID', DATE '2024-03-29', 97.00);
INSERT INTO claims VALUES (26, 5, 26, '99215', DATE '2024-03-22', DATE '2024-03-20', 180.00, 1, 'E78.5', 'PAID', DATE '2024-04-05', 180.00);
INSERT INTO claims VALUES (27, 5, 30, '99213', DATE '2024-04-01', DATE '2024-03-29', 88.00, 1, 'M54.5', 'PAID', DATE '2024-04-15', 88.00);
INSERT INTO claims VALUES (28, 6, 7, '90837', DATE '2024-01-20', DATE '2024-01-18', 125.00, 1, 'F32.1', 'PAID', DATE '2024-02-03', 125.00);
INSERT INTO claims VALUES (29, 6, 14, '90834', DATE '2024-01-27', DATE '2024-01-25', 105.00, 1, 'F41.1', 'PAID', DATE '2024-02-10', 105.00);
INSERT INTO claims VALUES (30, 6, 20, '90837', DATE '2024-02-03', DATE '2024-02-01', 135.00, 1, 'F32.1', 'PAID', DATE '2024-02-17', 135.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting legitimate claims (batch 4 of 7)..."
oracle_query "INSERT INTO claims VALUES (31, 6, 25, '90834', DATE '2024-02-10', DATE '2024-02-08', 98.00, 1, 'F41.1', 'PAID', DATE '2024-02-24', 98.00);
INSERT INTO claims VALUES (32, 6, 32, '90837', DATE '2024-02-17', DATE '2024-02-15', 128.00, 1, 'F33.0', 'PAID', DATE '2024-03-02', 128.00);
INSERT INTO claims VALUES (33, 6, 36, '90834', DATE '2024-03-02', DATE '2024-02-29', 102.00, 1, 'F41.1', 'PAID', DATE '2024-03-16', 102.00);
INSERT INTO claims VALUES (34, 6, 40, '90837', DATE '2024-03-16', DATE '2024-03-14', 132.00, 1, 'F32.9', 'PAID', DATE '2024-03-30', 132.00);
INSERT INTO claims VALUES (35, 7, 2, '99283', DATE '2024-01-07', DATE '2024-01-07', 148.00, 1, 'S61.0', 'PAID', DATE '2024-01-21', 148.00);
INSERT INTO claims VALUES (36, 7, 8, '99284', DATE '2024-01-21', DATE '2024-01-21', 245.00, 1, 'S52.5', 'PAID', DATE '2024-02-04', 245.00);
INSERT INTO claims VALUES (37, 7, 16, '99282', DATE '2024-02-11', DATE '2024-02-11', 92.00, 1, 'T78.2', 'PAID', DATE '2024-02-25', 92.00);
INSERT INTO claims VALUES (38, 7, 24, '99283', DATE '2024-03-03', DATE '2024-03-03', 150.00, 1, 'R10.0', 'PAID', DATE '2024-03-17', 150.00);
INSERT INTO claims VALUES (39, 7, 33, '99285', DATE '2024-03-17', DATE '2024-03-17', 410.00, 1, 'I21.0', 'PAID', DATE '2024-03-31', 410.00);
INSERT INTO claims VALUES (40, 7, 41, '99281', DATE '2024-04-14', DATE '2024-04-14', 52.00, 1, 'J06.9', 'PAID', DATE '2024-04-28', 52.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting legitimate claims (batch 5 of 7)..."
oracle_query "INSERT INTO claims VALUES (41, 7, 45, '99284', DATE '2024-05-05', DATE '2024-05-05', 260.00, 1, 'S82.0', 'PAID', DATE '2024-05-19', 260.00);
INSERT INTO claims VALUES (42, 8, 3, '70553', DATE '2024-02-01', DATE '2024-01-30', 480.00, 1, 'G43.9', 'PAID', DATE '2024-02-15', 480.00);
INSERT INTO claims VALUES (43, 8, 11, '71260', DATE '2024-02-15', DATE '2024-02-13', 310.00, 1, 'R91.1', 'PAID', DATE '2024-03-01', 310.00);
INSERT INTO claims VALUES (44, 8, 19, '70553', DATE '2024-03-01', DATE '2024-02-28', 520.00, 1, 'R51', 'PAID', DATE '2024-03-15', 520.00);
INSERT INTO claims VALUES (45, 8, 28, '71260', DATE '2024-03-22', DATE '2024-03-20', 290.00, 1, 'J18.9', 'PAID', DATE '2024-04-05', 290.00);
INSERT INTO claims VALUES (46, 8, 35, '70553', DATE '2024-04-12', DATE '2024-04-10', 510.00, 1, 'G40.9', 'PAID', DATE '2024-04-26', 510.00);
INSERT INTO claims VALUES (47, 8, 43, '71260', DATE '2024-05-03', DATE '2024-05-01', 305.00, 1, 'R91.1', 'PAID', DATE '2024-05-17', 305.00);
INSERT INTO claims VALUES (48, 9, 5, '45380', DATE '2024-01-25', DATE '2024-01-22', 415.00, 1, 'K63.5', 'PAID', DATE '2024-02-08', 415.00);
INSERT INTO claims VALUES (49, 9, 13, '43239', DATE '2024-02-20', DATE '2024-02-17', 340.00, 1, 'K21.0', 'PAID', DATE '2024-03-05', 340.00);
INSERT INTO claims VALUES (50, 9, 21, '45380', DATE '2024-03-15', DATE '2024-03-12', 390.00, 1, 'K63.5', 'PAID', DATE '2024-03-29', 390.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting legitimate claims (batch 6 of 7)..."
oracle_query "INSERT INTO claims VALUES (51, 9, 29, '43239', DATE '2024-04-10', DATE '2024-04-08', 360.00, 1, 'K25.9', 'PAID', DATE '2024-04-24', 360.00);
INSERT INTO claims VALUES (52, 9, 38, '45380', DATE '2024-05-08', DATE '2024-05-06', 405.00, 1, 'D12.6', 'PAID', DATE '2024-05-22', 405.00);
INSERT INTO claims VALUES (53, 14, 6, '93000', DATE '2024-01-18', DATE '2024-01-16', 24.00, 1, 'R00.0', 'PAID', DATE '2024-02-01', 24.00);
INSERT INTO claims VALUES (54, 14, 15, '93000', DATE '2024-02-08', DATE '2024-02-06', 26.00, 1, 'I49.9', 'PAID', DATE '2024-02-22', 26.00);
INSERT INTO claims VALUES (55, 14, 26, '93000', DATE '2024-03-01', DATE '2024-02-28', 25.00, 1, 'R00.1', 'PAID', DATE '2024-03-15', 25.00);
INSERT INTO claims VALUES (56, 14, 33, '93000', DATE '2024-03-22', DATE '2024-03-20', 27.00, 1, 'I49.9', 'PAID', DATE '2024-04-05', 27.00);
INSERT INTO claims VALUES (57, 14, 42, '93000', DATE '2024-04-12', DATE '2024-04-10', 23.50, 1, 'R00.0', 'PAID', DATE '2024-04-26', 23.50);
INSERT INTO claims VALUES (58, 14, 47, '93000', DATE '2024-05-03', DATE '2024-05-01', 25.50, 1, 'I25.10', 'PAID', DATE '2024-05-17', 25.50);
INSERT INTO claims VALUES (59, 1, 13, '99213', DATE '2024-04-05', DATE '2024-04-03', 94.00, 1, 'J06.9', 'PAID', DATE '2024-04-19', 94.00);
INSERT INTO claims VALUES (60, 1, 17, '99214', DATE '2024-04-12', DATE '2024-04-10', 127.00, 1, 'E11.9', 'PAID', DATE '2024-04-26', 127.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting legitimate claims (batch 7 of 7)..."
oracle_query "INSERT INTO claims VALUES (61, 1, 21, '99213', DATE '2024-04-19', DATE '2024-04-17', 90.50, 1, 'M54.5', 'PAID', DATE '2024-05-03', 90.50);
INSERT INTO claims VALUES (62, 1, 26, '99214', DATE '2024-05-03', DATE '2024-05-01', 131.00, 1, 'I10', 'PAID', DATE '2024-05-17', 131.00);
INSERT INTO claims VALUES (63, 2, 22, '99213', DATE '2024-03-08', DATE '2024-03-06', 93.50, 1, 'J02.9', 'PAID', DATE '2024-03-22', 93.50);
INSERT INTO claims VALUES (64, 2, 27, '99214', DATE '2024-03-15', DATE '2024-03-13', 136.00, 1, 'E78.5', 'PAID', DATE '2024-03-29', 136.00);
INSERT INTO claims VALUES (65, 2, 30, '99213', DATE '2024-04-05', DATE '2024-04-03', 91.00, 1, 'N39.0', 'PAID', DATE '2024-04-19', 91.00);
INSERT INTO claims VALUES (66, 2, 34, '99214', DATE '2024-04-19', DATE '2024-04-17', 133.00, 1, 'I10', 'PAID', DATE '2024-05-03', 133.00);
INSERT INTO claims VALUES (67, 3, 27, '99213', DATE '2024-04-08', DATE '2024-04-05', 88.00, 1, 'R05.9', 'PAID', DATE '2024-04-22', 88.00);
INSERT INTO claims VALUES (68, 3, 32, '99214', DATE '2024-04-22', DATE '2024-04-19', 141.00, 1, 'E11.65', 'PAID', DATE '2024-05-06', 141.00);
INSERT INTO claims VALUES (69, 3, 37, '99213', DATE '2024-05-06', DATE '2024-05-03', 86.00, 1, 'J06.9', 'PAID', DATE '2024-05-20', 86.00);
INSERT INTO claims VALUES (70, 3, 40, '99214', DATE '2024-05-20', DATE '2024-05-17', 137.00, 1, 'M79.3', 'PAID', DATE '2024-06-03', 137.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# More legitimate claims from various providers
echo "Inserting more legitimate claims (batch 8)..."
oracle_query "INSERT INTO claims VALUES (71, 5, 33, '99214', DATE '2024-04-15', DATE '2024-04-12', 131.00, 1, 'E11.9', 'PAID', DATE '2024-04-29', 131.00);
INSERT INTO claims VALUES (72, 5, 37, '99213', DATE '2024-04-29', DATE '2024-04-26', 95.00, 1, 'J02.9', 'PAID', DATE '2024-05-13', 95.00);
INSERT INTO claims VALUES (73, 5, 41, '99214', DATE '2024-05-13', DATE '2024-05-10', 128.00, 1, 'I10', 'PAID', DATE '2024-05-27', 128.00);
INSERT INTO claims VALUES (74, 5, 44, '99213', DATE '2024-05-27', DATE '2024-05-24', 93.00, 1, 'R10.9', 'PAID', DATE '2024-06-10', 93.00);
INSERT INTO claims VALUES (75, 1, 30, '99213', DATE '2024-05-17', DATE '2024-05-15', 89.00, 1, 'J20.9', 'PAID', DATE '2024-05-31', 89.00);
INSERT INTO claims VALUES (76, 1, 33, '99214', DATE '2024-05-31', DATE '2024-05-29', 134.00, 1, 'E11.9', 'PAID', DATE '2024-06-14', 134.00);
INSERT INTO claims VALUES (77, 2, 37, '99213', DATE '2024-05-10', DATE '2024-05-08', 92.00, 1, 'M54.5', 'PAID', DATE '2024-05-24', 92.00);
INSERT INTO claims VALUES (78, 2, 41, '99214', DATE '2024-05-24', DATE '2024-05-22', 130.00, 1, 'I10', 'PAID', DATE '2024-06-07', 130.00);
INSERT INTO claims VALUES (79, 3, 44, '99213', DATE '2024-06-03', DATE '2024-05-31', 94.00, 1, 'J06.9', 'PAID', DATE '2024-06-17', 94.00);
INSERT INTO claims VALUES (80, 3, 47, '99214', DATE '2024-06-17', DATE '2024-06-14', 129.00, 1, 'E78.5', 'PAID', DATE '2024-07-01', 129.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 9)..."
oracle_query "INSERT INTO claims VALUES (81, 5, 47, '99213', DATE '2024-06-10', DATE '2024-06-07', 96.00, 1, 'R05.9', 'PAID', DATE '2024-06-24', 96.00);
INSERT INTO claims VALUES (82, 5, 50, '99214', DATE '2024-06-24', DATE '2024-06-21', 135.00, 1, 'I10', 'PAID', DATE '2024-07-08', 135.00);
INSERT INTO claims VALUES (83, 1, 37, '99213', DATE '2024-06-14', DATE '2024-06-12', 91.00, 1, 'N39.0', 'PAID', DATE '2024-06-28', 91.00);
INSERT INTO claims VALUES (84, 1, 42, '99214', DATE '2024-06-28', DATE '2024-06-26', 133.00, 1, 'E11.9', 'PAID', DATE '2024-07-12', 133.00);
INSERT INTO claims VALUES (85, 2, 44, '99213', DATE '2024-06-07', DATE '2024-06-05', 89.00, 1, 'J06.9', 'PAID', DATE '2024-06-21', 89.00);
INSERT INTO claims VALUES (86, 2, 48, '99214', DATE '2024-06-21', DATE '2024-06-19', 132.00, 1, 'M79.3', 'PAID', DATE '2024-07-05', 132.00);
INSERT INTO claims VALUES (87, 3, 50, '99213', DATE '2024-07-01', DATE '2024-06-28', 93.00, 1, 'J02.9', 'PAID', DATE '2024-07-15', 93.00);
INSERT INTO claims VALUES (88, 3, 1, '99214', DATE '2024-07-15', DATE '2024-07-12', 128.00, 1, 'E11.65', 'PAID', DATE '2024-07-29', 128.00);
INSERT INTO claims VALUES (89, 5, 2, '99213', DATE '2024-07-08', DATE '2024-07-05', 90.00, 1, 'R10.9', 'PAID', DATE '2024-07-22', 90.00);
INSERT INTO claims VALUES (90, 5, 6, '99214', DATE '2024-07-22', DATE '2024-07-19', 136.00, 1, 'I10', 'PAID', DATE '2024-08-05', 136.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 10)..."
oracle_query "INSERT INTO claims VALUES (91, 1, 46, '99213', DATE '2024-07-12', DATE '2024-07-10', 95.00, 1, 'J06.9', 'PAID', DATE '2024-07-26', 95.00);
INSERT INTO claims VALUES (92, 1, 49, '99214', DATE '2024-07-26', DATE '2024-07-24', 130.00, 1, 'E11.9', 'PAID', DATE '2024-08-09', 130.00);
INSERT INTO claims VALUES (93, 2, 50, '99213', DATE '2024-07-19', DATE '2024-07-17', 92.00, 1, 'M54.5', 'PAID', DATE '2024-08-02', 92.00);
INSERT INTO claims VALUES (94, 2, 1, '99214', DATE '2024-08-02', DATE '2024-07-31', 134.00, 1, 'I10', 'PAID', DATE '2024-08-16', 134.00);
INSERT INTO claims VALUES (95, 3, 5, '99213', DATE '2024-08-05', DATE '2024-08-02', 88.00, 1, 'J20.9', 'PAID', DATE '2024-08-19', 88.00);
INSERT INTO claims VALUES (96, 3, 9, '99214', DATE '2024-08-19', DATE '2024-08-16', 141.00, 1, 'E78.5', 'PAID', DATE '2024-09-02', 141.00);
INSERT INTO claims VALUES (97, 5, 11, '99213', DATE '2024-08-12', DATE '2024-08-09', 94.00, 1, 'R05.9', 'PAID', DATE '2024-08-26', 94.00);
INSERT INTO claims VALUES (98, 5, 15, '99214', DATE '2024-08-26', DATE '2024-08-23', 129.00, 1, 'I10', 'PAID', DATE '2024-09-09', 129.00);
INSERT INTO claims VALUES (99, 1, 3, '99213', DATE '2024-08-16', DATE '2024-08-14', 91.00, 1, 'N39.0', 'PAID', DATE '2024-08-30', 91.00);
INSERT INTO claims VALUES (100, 1, 7, '99214', DATE '2024-08-30', DATE '2024-08-28', 127.00, 1, 'E11.9', 'PAID', DATE '2024-09-13', 127.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 11)..."
oracle_query "INSERT INTO claims VALUES (101, 2, 9, '99213', DATE '2024-08-23', DATE '2024-08-21', 93.00, 1, 'J06.9', 'PAID', DATE '2024-09-06', 93.00);
INSERT INTO claims VALUES (102, 2, 13, '99214', DATE '2024-09-06', DATE '2024-09-04', 131.00, 1, 'M79.3', 'PAID', DATE '2024-09-20', 131.00);
INSERT INTO claims VALUES (103, 3, 15, '99213', DATE '2024-09-02', DATE '2024-08-30', 90.00, 1, 'J02.9', 'PAID', DATE '2024-09-16', 90.00);
INSERT INTO claims VALUES (104, 3, 19, '99214', DATE '2024-09-16', DATE '2024-09-13', 138.00, 1, 'E11.9', 'PAID', DATE '2024-09-30', 138.00);
INSERT INTO claims VALUES (105, 5, 21, '99213', DATE '2024-09-09', DATE '2024-09-06', 87.00, 1, 'R10.9', 'PAID', DATE '2024-09-23', 87.00);
INSERT INTO claims VALUES (106, 5, 24, '99214', DATE '2024-09-23', DATE '2024-09-20', 133.00, 1, 'I10', 'PAID', DATE '2024-10-07', 133.00);
INSERT INTO claims VALUES (107, 1, 12, '99203', DATE '2024-03-18', DATE '2024-03-15', 115.00, 1, 'E11.9', 'PAID', DATE '2024-04-01', 115.00);
INSERT INTO claims VALUES (108, 1, 16, '99204', DATE '2024-04-25', DATE '2024-04-23', 162.00, 1, 'I10', 'PAID', DATE '2024-05-09', 162.00);
INSERT INTO claims VALUES (109, 2, 20, '99203', DATE '2024-05-16', DATE '2024-05-14', 108.00, 1, 'J06.9', 'PAID', DATE '2024-05-30', 108.00);
INSERT INTO claims VALUES (110, 2, 25, '99204', DATE '2024-06-13', DATE '2024-06-11', 170.00, 1, 'E78.5', 'PAID', DATE '2024-06-27', 170.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 12)..."
oracle_query "INSERT INTO claims VALUES (111, 3, 28, '99203', DATE '2024-07-11', DATE '2024-07-09', 112.00, 1, 'M54.5', 'PAID', DATE '2024-07-25', 112.00);
INSERT INTO claims VALUES (112, 3, 34, '99204', DATE '2024-08-08', DATE '2024-08-06', 165.00, 1, 'E11.65', 'PAID', DATE '2024-08-22', 165.00);
INSERT INTO claims VALUES (113, 5, 36, '99203', DATE '2024-09-05', DATE '2024-09-03', 114.00, 1, 'N39.0', 'PAID', DATE '2024-09-19', 114.00);
INSERT INTO claims VALUES (114, 5, 39, '99204', DATE '2024-10-03', DATE '2024-10-01', 168.00, 1, 'R05.9', 'PAID', DATE '2024-10-17', 168.00);
INSERT INTO claims VALUES (115, 6, 44, '90837', DATE '2024-04-06', DATE '2024-04-04', 133.00, 1, 'F32.1', 'PAID', DATE '2024-04-20', 133.00);
INSERT INTO claims VALUES (116, 6, 48, '90834', DATE '2024-04-20', DATE '2024-04-18', 97.00, 1, 'F41.1', 'PAID', DATE '2024-05-04', 97.00);
INSERT INTO claims VALUES (117, 6, 3, '90837', DATE '2024-05-04', DATE '2024-05-02', 131.00, 1, 'F33.0', 'PAID', DATE '2024-05-18', 131.00);
INSERT INTO claims VALUES (118, 6, 12, '90834', DATE '2024-05-18', DATE '2024-05-16', 103.00, 1, 'F41.1', 'PAID', DATE '2024-06-01', 103.00);
INSERT INTO claims VALUES (119, 7, 49, '99283', DATE '2024-06-08', DATE '2024-06-08', 142.00, 1, 'S93.4', 'PAID', DATE '2024-06-22', 142.00);
INSERT INTO claims VALUES (120, 7, 3, '99282', DATE '2024-07-14', DATE '2024-07-14', 98.00, 1, 'T78.2', 'PAID', DATE '2024-07-28', 98.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 13)..."
oracle_query "INSERT INTO claims VALUES (121, 7, 10, '99284', DATE '2024-08-11', DATE '2024-08-11', 255.00, 1, 'R07.9', 'PAID', DATE '2024-08-25', 255.00);
INSERT INTO claims VALUES (122, 7, 18, '99281', DATE '2024-09-22', DATE '2024-09-22', 53.00, 1, 'J06.9', 'PAID', DATE '2024-10-06', 53.00);
INSERT INTO claims VALUES (123, 8, 22, '70553', DATE '2024-05-20', DATE '2024-05-17', 495.00, 1, 'G43.9', 'PAID', DATE '2024-06-03', 495.00);
INSERT INTO claims VALUES (124, 8, 30, '71260', DATE '2024-06-14', DATE '2024-06-12', 315.00, 1, 'J18.9', 'PAID', DATE '2024-06-28', 315.00);
INSERT INTO claims VALUES (125, 8, 38, '70553', DATE '2024-07-12', DATE '2024-07-10', 505.00, 1, 'R51', 'PAID', DATE '2024-07-26', 505.00);
INSERT INTO claims VALUES (126, 8, 46, '71260', DATE '2024-08-09', DATE '2024-08-07', 298.00, 1, 'R91.1', 'PAID', DATE '2024-08-23', 298.00);
INSERT INTO claims VALUES (127, 9, 33, '45380', DATE '2024-06-07', DATE '2024-06-05', 395.00, 1, 'D12.6', 'PAID', DATE '2024-06-21', 395.00);
INSERT INTO claims VALUES (128, 9, 41, '43239', DATE '2024-07-05', DATE '2024-07-03', 355.00, 1, 'K21.0', 'PAID', DATE '2024-07-19', 355.00);
INSERT INTO claims VALUES (129, 9, 49, '45380', DATE '2024-08-02', DATE '2024-07-31', 410.00, 1, 'K63.5', 'PAID', DATE '2024-08-16', 410.00);
INSERT INTO claims VALUES (130, 9, 6, '43239', DATE '2024-09-06', DATE '2024-09-04', 345.00, 1, 'K25.9', 'PAID', DATE '2024-09-20', 345.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 14)..."
oracle_query "INSERT INTO claims VALUES (131, 14, 1, '93000', DATE '2024-06-05', DATE '2024-06-03', 24.50, 1, 'R00.0', 'PAID', DATE '2024-06-19', 24.50);
INSERT INTO claims VALUES (132, 14, 9, '93000', DATE '2024-07-03', DATE '2024-07-01', 26.50, 1, 'I49.9', 'PAID', DATE '2024-07-17', 26.50);
INSERT INTO claims VALUES (133, 14, 17, '93000', DATE '2024-08-01', DATE '2024-07-30', 25.00, 1, 'R00.1', 'PAID', DATE '2024-08-15', 25.00);
INSERT INTO claims VALUES (134, 14, 26, '93000', DATE '2024-09-05', DATE '2024-09-03', 24.00, 1, 'I25.10', 'PAID', DATE '2024-09-19', 24.00);
INSERT INTO claims VALUES (135, 14, 35, '93000', DATE '2024-10-04', DATE '2024-10-02', 27.00, 1, 'R00.0', 'PAID', DATE '2024-10-18', 27.00);
INSERT INTO claims VALUES (136, 4, 35, '27447', DATE '2024-07-25', DATE '2024-07-19', 1465.00, 1, 'M17.11', 'PAID', DATE '2024-08-08', 1465.00);
INSERT INTO claims VALUES (137, 4, 43, '27130', DATE '2024-08-30', DATE '2024-08-24', 1415.00, 1, 'M16.11', 'PAID', DATE '2024-09-13', 1415.00);
INSERT INTO claims VALUES (138, 4, 49, '27447', DATE '2024-10-10', DATE '2024-10-04', 1500.00, 1, 'M17.12', 'PAID', DATE '2024-10-24', 1500.00);
INSERT INTO claims VALUES (139, 1, 10, '99213', DATE '2024-09-13', DATE '2024-09-11', 93.00, 1, 'J06.9', 'PAID', DATE '2024-09-27', 93.00);
INSERT INTO claims VALUES (140, 1, 15, '99214', DATE '2024-09-27', DATE '2024-09-25', 132.00, 1, 'E11.9', 'PAID', DATE '2024-10-11', 132.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 15)..."
oracle_query "INSERT INTO claims VALUES (141, 2, 19, '99213', DATE '2024-09-20', DATE '2024-09-18', 91.00, 1, 'R10.9', 'PAID', DATE '2024-10-04', 91.00);
INSERT INTO claims VALUES (142, 2, 24, '99214', DATE '2024-10-04', DATE '2024-10-02', 130.00, 1, 'I10', 'PAID', DATE '2024-10-18', 130.00);
INSERT INTO claims VALUES (143, 3, 26, '99213', DATE '2024-10-07', DATE '2024-10-04', 87.00, 1, 'J02.9', 'PAID', DATE '2024-10-21', 87.00);
INSERT INTO claims VALUES (144, 3, 30, '99214', DATE '2024-10-21', DATE '2024-10-18', 139.00, 1, 'E11.65', 'PAID', DATE '2024-11-04', 139.00);
INSERT INTO claims VALUES (145, 5, 34, '99213', DATE '2024-10-14', DATE '2024-10-11', 96.00, 1, 'M54.5', 'PAID', DATE '2024-10-28', 96.00);
INSERT INTO claims VALUES (146, 5, 38, '99214', DATE '2024-10-28', DATE '2024-10-25', 128.00, 1, 'I10', 'PAID', DATE '2024-11-11', 128.00);
INSERT INTO claims VALUES (147, 1, 20, '99213', DATE '2024-10-11', DATE '2024-10-09', 90.00, 1, 'J20.9', 'PAID', DATE '2024-10-25', 90.00);
INSERT INTO claims VALUES (148, 1, 24, '99214', DATE '2024-10-25', DATE '2024-10-23', 135.00, 1, 'E78.5', 'PAID', DATE '2024-11-08', 135.00);
INSERT INTO claims VALUES (149, 2, 28, '99213', DATE '2024-10-18', DATE '2024-10-16', 94.00, 1, 'J06.9', 'PAID', DATE '2024-11-01', 94.00);
INSERT INTO claims VALUES (150, 2, 32, '99214', DATE '2024-11-01', DATE '2024-10-30', 131.00, 1, 'M79.3', 'PAID', DATE '2024-11-15', 131.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 16)..."
oracle_query "INSERT INTO claims VALUES (151, 3, 36, '99213', DATE '2024-11-04', DATE '2024-11-01', 92.00, 1, 'N39.0', 'PAID', DATE '2024-11-18', 92.00);
INSERT INTO claims VALUES (152, 3, 39, '99214', DATE '2024-11-18', DATE '2024-11-15', 137.00, 1, 'E11.9', 'PAID', DATE '2024-12-02', 137.00);
INSERT INTO claims VALUES (153, 5, 42, '99213', DATE '2024-11-11', DATE '2024-11-08', 95.00, 1, 'R05.9', 'PAID', DATE '2024-11-25', 95.00);
INSERT INTO claims VALUES (154, 5, 45, '99214', DATE '2024-11-25', DATE '2024-11-22', 134.00, 1, 'I10', 'PAID', DATE '2024-12-09', 134.00);
INSERT INTO claims VALUES (155, 6, 18, '90837', DATE '2024-06-01', DATE '2024-05-30', 129.00, 1, 'F32.1', 'PAID', DATE '2024-06-15', 129.00);
INSERT INTO claims VALUES (156, 6, 27, '90834', DATE '2024-06-15', DATE '2024-06-13', 104.00, 1, 'F41.1', 'PAID', DATE '2024-06-29', 104.00);
INSERT INTO claims VALUES (157, 6, 34, '90837', DATE '2024-07-06', DATE '2024-07-04', 127.00, 1, 'F33.0', 'PAID', DATE '2024-07-20', 127.00);
INSERT INTO claims VALUES (158, 6, 39, '90834', DATE '2024-07-20', DATE '2024-07-18', 101.00, 1, 'F41.1', 'PAID', DATE '2024-08-03', 101.00);
INSERT INTO claims VALUES (159, 6, 44, '90837', DATE '2024-08-10', DATE '2024-08-08', 134.00, 1, 'F32.9', 'PAID', DATE '2024-08-24', 134.00);
INSERT INTO claims VALUES (160, 6, 50, '90834', DATE '2024-08-24', DATE '2024-08-22', 99.00, 1, 'F41.1', 'PAID', DATE '2024-09-07', 99.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 17)..."
oracle_query "INSERT INTO claims VALUES (161, 7, 22, '99285', DATE '2024-10-13', DATE '2024-10-13', 395.00, 1, 'I21.0', 'PAID', DATE '2024-10-27', 395.00);
INSERT INTO claims VALUES (162, 7, 29, '99283', DATE '2024-11-09', DATE '2024-11-09', 148.00, 1, 'S61.0', 'PAID', DATE '2024-11-23', 148.00);
INSERT INTO claims VALUES (163, 8, 2, '71260', DATE '2024-09-06', DATE '2024-09-04', 308.00, 1, 'R91.1', 'PAID', DATE '2024-09-20', 308.00);
INSERT INTO claims VALUES (164, 8, 14, '70553', DATE '2024-10-04', DATE '2024-10-02', 515.00, 1, 'G43.9', 'PAID', DATE '2024-10-18', 515.00);
INSERT INTO claims VALUES (165, 9, 17, '43239', DATE '2024-10-11', DATE '2024-10-09', 348.00, 1, 'K21.0', 'PAID', DATE '2024-10-25', 348.00);
INSERT INTO claims VALUES (166, 9, 24, '45380', DATE '2024-11-08', DATE '2024-11-06', 402.00, 1, 'K63.5', 'PAID', DATE '2024-11-22', 402.00);
INSERT INTO claims VALUES (167, 14, 43, '93000', DATE '2024-11-01', DATE '2024-10-30', 25.50, 1, 'I49.9', 'PAID', DATE '2024-11-15', 25.50);
INSERT INTO claims VALUES (168, 14, 50, '93000', DATE '2024-11-22', DATE '2024-11-20', 24.00, 1, 'R00.0', 'PAID', DATE '2024-12-06', 24.00);
INSERT INTO claims VALUES (169, 1, 28, '99213', DATE '2024-11-08', DATE '2024-11-06', 92.00, 1, 'J06.9', 'PAID', DATE '2024-11-22', 92.00);
INSERT INTO claims VALUES (170, 1, 35, '99214', DATE '2024-11-22', DATE '2024-11-20', 130.00, 1, 'I10', 'PAID', DATE '2024-12-06', 130.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 18)..."
oracle_query "INSERT INTO claims VALUES (171, 2, 38, '99213', DATE '2024-11-15', DATE '2024-11-13', 89.00, 1, 'M54.5', 'PAID', DATE '2024-11-29', 89.00);
INSERT INTO claims VALUES (172, 2, 42, '99214', DATE '2024-11-29', DATE '2024-11-27', 136.00, 1, 'E11.9', 'PAID', DATE '2024-12-13', 136.00);
INSERT INTO claims VALUES (173, 3, 45, '99213', DATE '2024-12-02', DATE '2024-11-29', 91.00, 1, 'R10.9', 'PAID', DATE '2024-12-16', 91.00);
INSERT INTO claims VALUES (174, 3, 48, '99214', DATE '2024-12-16', DATE '2024-12-13', 140.00, 1, 'E78.5', 'PAID', DATE '2024-12-30', 140.00);
INSERT INTO claims VALUES (175, 5, 49, '99213', DATE '2024-12-09', DATE '2024-12-06', 88.00, 1, 'J20.9', 'PAID', DATE '2024-12-23', 88.00);
INSERT INTO claims VALUES (176, 5, 1, '99214', DATE '2024-12-23', DATE '2024-12-20', 133.00, 1, 'I10', 'PAID', DATE '2025-01-06', 133.00);
INSERT INTO claims VALUES (177, 1, 38, '99205', DATE '2024-06-07', DATE '2024-06-05', 215.00, 1, 'E11.9', 'PAID', DATE '2024-06-21', 215.00);
INSERT INTO claims VALUES (178, 2, 40, '99205', DATE '2024-07-18', DATE '2024-07-16', 208.00, 1, 'I10', 'PAID', DATE '2024-08-01', 208.00);
INSERT INTO claims VALUES (179, 3, 42, '99203', DATE '2024-08-22', DATE '2024-08-20', 113.00, 1, 'J06.9', 'PAID', DATE '2024-09-05', 113.00);
INSERT INTO claims VALUES (180, 5, 46, '99204', DATE '2024-09-19', DATE '2024-09-17', 171.00, 1, 'E78.5', 'PAID', DATE '2024-10-03', 171.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 19 - additional office visits)..."
oracle_query "INSERT INTO claims VALUES (181, 1, 44, '99213', DATE '2024-12-06', DATE '2024-12-04', 94.00, 1, 'N39.0', 'PAID', DATE '2024-12-20', 94.00);
INSERT INTO claims VALUES (182, 2, 46, '99214', DATE '2024-12-13', DATE '2024-12-11', 129.00, 1, 'M79.3', 'PAID', DATE '2024-12-27', 129.00);
INSERT INTO claims VALUES (183, 3, 2, '99213', DATE '2024-12-20', DATE '2024-12-18', 96.00, 1, 'J02.9', 'PAID', DATE '2025-01-03', 96.00);
INSERT INTO claims VALUES (184, 5, 4, '99214', DATE '2024-12-27', DATE '2024-12-24', 131.00, 1, 'E11.65', 'PAID', DATE '2025-01-10', 131.00);
INSERT INTO claims VALUES (185, 1, 48, '99213', DATE '2024-03-29', DATE '2024-03-27', 89.00, 1, 'J06.9', 'PAID', DATE '2024-04-12', 89.00);
INSERT INTO claims VALUES (186, 2, 5, '99214', DATE '2024-04-12', DATE '2024-04-10', 135.00, 1, 'I10', 'PAID', DATE '2024-04-26', 135.00);
INSERT INTO claims VALUES (187, 3, 10, '99213', DATE '2024-05-10', DATE '2024-05-08', 93.00, 1, 'M54.5', 'PAID', DATE '2024-05-24', 93.00);
INSERT INTO claims VALUES (188, 5, 14, '99214', DATE '2024-06-07', DATE '2024-06-05', 128.00, 1, 'E11.9', 'PAID', DATE '2024-06-21', 128.00);
INSERT INTO claims VALUES (189, 1, 50, '99213', DATE '2024-07-05', DATE '2024-07-03', 90.00, 1, 'R05.9', 'PAID', DATE '2024-07-19', 90.00);
INSERT INTO claims VALUES (190, 2, 6, '99214', DATE '2024-08-09', DATE '2024-08-07', 132.00, 1, 'N39.0', 'PAID', DATE '2024-08-23', 132.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting more legitimate claims (batch 20 - filling to ~220)..."
oracle_query "INSERT INTO claims VALUES (191, 3, 11, '99213', DATE '2024-09-13', DATE '2024-09-11', 95.00, 1, 'J20.9', 'PAID', DATE '2024-09-27', 95.00);
INSERT INTO claims VALUES (192, 5, 17, '99214', DATE '2024-10-18', DATE '2024-10-16', 137.00, 1, 'E78.5', 'PAID', DATE '2024-11-01', 137.00);
INSERT INTO claims VALUES (193, 1, 6, '99213', DATE '2024-11-15', DATE '2024-11-13', 91.00, 1, 'J06.9', 'PAID', DATE '2024-11-29', 91.00);
INSERT INTO claims VALUES (194, 2, 11, '99214', DATE '2024-12-06', DATE '2024-12-04', 134.00, 1, 'I10', 'PAID', DATE '2024-12-20', 134.00);
INSERT INTO claims VALUES (195, 3, 16, '99213', DATE '2024-01-19', DATE '2024-01-17', 88.00, 1, 'R10.9', 'PAID', DATE '2024-02-02', 88.00);
INSERT INTO claims VALUES (196, 5, 20, '99214', DATE '2024-02-16', DATE '2024-02-14', 130.00, 1, 'M79.3', 'PAID', DATE '2024-03-01', 130.00);
INSERT INTO claims VALUES (197, 1, 23, '99213', DATE '2024-03-15', DATE '2024-03-13', 92.00, 1, 'J02.9', 'PAID', DATE '2024-03-29', 92.00);
INSERT INTO claims VALUES (198, 2, 29, '99214', DATE '2024-04-26', DATE '2024-04-24', 136.00, 1, 'E11.65', 'PAID', DATE '2024-05-10', 136.00);
INSERT INTO claims VALUES (199, 3, 33, '99213', DATE '2024-05-24', DATE '2024-05-22', 94.00, 1, 'M54.5', 'PAID', DATE '2024-06-07', 94.00);
INSERT INTO claims VALUES (200, 5, 35, '99214', DATE '2024-06-28', DATE '2024-06-26', 131.00, 1, 'I10', 'PAID', DATE '2024-07-12', 131.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting final legitimate claims (batch 21)..."
oracle_query "INSERT INTO claims VALUES (201, 1, 39, '99213', DATE '2024-08-02', DATE '2024-07-31', 93.00, 1, 'J06.9', 'PAID', DATE '2024-08-16', 93.00);
INSERT INTO claims VALUES (202, 2, 43, '99214', DATE '2024-09-13', DATE '2024-09-11', 129.00, 1, 'E11.9', 'PAID', DATE '2024-09-27', 129.00);
INSERT INTO claims VALUES (203, 3, 46, '99213', DATE '2024-10-11', DATE '2024-10-09', 90.00, 1, 'N39.0', 'PAID', DATE '2024-10-25', 90.00);
INSERT INTO claims VALUES (204, 5, 48, '99214', DATE '2024-11-08', DATE '2024-11-06', 133.00, 1, 'I10', 'PAID', DATE '2024-11-22', 133.00);
INSERT INTO claims VALUES (205, 1, 4, '99213', DATE '2024-12-13', DATE '2024-12-11', 91.00, 1, 'R05.9', 'PAID', DATE '2024-12-27', 91.00);
INSERT INTO claims VALUES (206, 2, 8, '99214', DATE '2024-01-29', DATE '2024-01-26', 131.00, 1, 'M79.3', 'PAID', DATE '2024-02-12', 131.00);
INSERT INTO claims VALUES (207, 3, 12, '99213', DATE '2024-03-08', DATE '2024-03-06', 88.00, 1, 'J06.9', 'PAID', DATE '2024-03-22', 88.00);
INSERT INTO claims VALUES (208, 5, 16, '99214', DATE '2024-04-19', DATE '2024-04-17', 135.00, 1, 'E11.9', 'PAID', DATE '2024-05-03', 135.00);
INSERT INTO claims VALUES (209, 1, 19, '99213', DATE '2024-05-31', DATE '2024-05-29', 94.00, 1, 'M54.5', 'PAID', DATE '2024-06-14', 94.00);
INSERT INTO claims VALUES (210, 2, 23, '99214', DATE '2024-07-05', DATE '2024-07-03', 130.00, 1, 'I10', 'PAID', DATE '2024-07-19', 130.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

echo "Inserting final legitimate claims (batch 22)..."
oracle_query "INSERT INTO claims VALUES (211, 3, 29, '99213', DATE '2024-08-16', DATE '2024-08-14', 92.00, 1, 'J02.9', 'PAID', DATE '2024-08-30', 92.00);
INSERT INTO claims VALUES (212, 5, 31, '99214', DATE '2024-09-27', DATE '2024-09-25', 136.00, 1, 'E78.5', 'PAID', DATE '2024-10-11', 136.00);
INSERT INTO claims VALUES (213, 1, 34, '99213', DATE '2024-10-25', DATE '2024-10-23', 89.00, 1, 'R10.9', 'PAID', DATE '2024-11-08', 89.00);
INSERT INTO claims VALUES (214, 2, 36, '99214', DATE '2024-11-22', DATE '2024-11-20', 133.00, 1, 'E11.65', 'PAID', DATE '2024-12-06', 133.00);
INSERT INTO claims VALUES (215, 3, 41, '99213', DATE '2024-12-06', DATE '2024-12-04', 95.00, 1, 'N39.0', 'PAID', DATE '2024-12-20', 95.00);
INSERT INTO claims VALUES (216, 5, 43, '99214', DATE '2024-12-20', DATE '2024-12-18', 128.00, 1, 'M79.3', 'PAID', DATE '2025-01-03', 128.00);
INSERT INTO claims VALUES (217, 1, 45, '99213', DATE '2024-02-09', DATE '2024-02-07', 93.00, 1, 'J06.9', 'PAID', DATE '2024-02-23', 93.00);
INSERT INTO claims VALUES (218, 2, 47, '99214', DATE '2024-03-22', DATE '2024-03-20', 131.00, 1, 'I10', 'PAID', DATE '2024-04-05', 131.00);
INSERT INTO claims VALUES (219, 3, 49, '99213', DATE '2024-04-19', DATE '2024-04-17', 90.00, 1, 'M54.5', 'PAID', DATE '2024-05-03', 90.00);
INSERT INTO claims VALUES (220, 5, 50, '99214', DATE '2024-05-17', DATE '2024-05-15', 134.00, 1, 'E11.9', 'PAID', DATE '2024-05-31', 134.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# ============================================================
# FRAUDULENT CLAIMS
# ============================================================

# --- Pattern A: Benford's Law Violation (providers 18-20) ---
# All amounts start with digits 5,6,7,8,9 to violate Benford's Law
echo "Inserting fraudulent claims - Pattern A (Benfords Law violation)..."
oracle_query "INSERT INTO claims VALUES (221, 18, 1, '99214', DATE '2024-02-05', DATE '2024-02-02', 555.00, 1, 'E11.9', 'PAID', DATE '2024-02-19', 555.00);
INSERT INTO claims VALUES (222, 18, 5, '99213', DATE '2024-03-08', DATE '2024-03-06', 665.00, 1, 'I10', 'PAID', DATE '2024-03-22', 665.00);
INSERT INTO claims VALUES (223, 18, 9, '99214', DATE '2024-04-12', DATE '2024-04-10', 789.00, 1, 'J06.9', 'PAID', DATE '2024-04-26', 789.00);
INSERT INTO claims VALUES (224, 18, 13, '99213', DATE '2024-05-17', DATE '2024-05-15', 890.00, 1, 'M54.5', 'PAID', DATE '2024-05-31', 890.00);
INSERT INTO claims VALUES (225, 18, 17, '99214', DATE '2024-06-21', DATE '2024-06-19', 950.00, 1, 'E78.5', 'PAID', DATE '2024-07-05', 950.00);
INSERT INTO claims VALUES (226, 18, 21, '99213', DATE '2024-07-26', DATE '2024-07-24', 567.00, 1, 'R05.9', 'PAID', DATE '2024-08-09', 567.00);
INSERT INTO claims VALUES (227, 18, 25, '99214', DATE '2024-08-30', DATE '2024-08-28', 678.00, 1, 'I10', 'PAID', DATE '2024-09-13', 678.00);
INSERT INTO claims VALUES (228, 19, 2, '99214', DATE '2024-02-09', DATE '2024-02-07', 599.00, 1, 'E11.9', 'PAID', DATE '2024-02-23', 599.00);
INSERT INTO claims VALUES (229, 19, 6, '99213', DATE '2024-03-15', DATE '2024-03-13', 756.00, 1, 'J06.9', 'PAID', DATE '2024-03-29', 756.00);
INSERT INTO claims VALUES (230, 19, 10, '99214', DATE '2024-04-19', DATE '2024-04-17', 845.00, 1, 'M79.3', 'PAID', DATE '2024-05-03', 845.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

oracle_query "INSERT INTO claims VALUES (231, 19, 14, '99213', DATE '2024-05-24', DATE '2024-05-22', 912.00, 1, 'N39.0', 'PAID', DATE '2024-06-07', 912.00);
INSERT INTO claims VALUES (232, 19, 18, '99214', DATE '2024-06-28', DATE '2024-06-26', 678.00, 1, 'I10', 'PAID', DATE '2024-07-12', 678.00);
INSERT INTO claims VALUES (233, 19, 22, '99213', DATE '2024-08-02', DATE '2024-07-31', 534.00, 1, 'E11.65', 'PAID', DATE '2024-08-16', 534.00);
INSERT INTO claims VALUES (234, 20, 3, '99214', DATE '2024-02-16', DATE '2024-02-14', 789.00, 1, 'I10', 'PAID', DATE '2024-03-01', 789.00);
INSERT INTO claims VALUES (235, 20, 7, '99213', DATE '2024-03-22', DATE '2024-03-20', 645.00, 1, 'J06.9', 'PAID', DATE '2024-04-05', 645.00);
INSERT INTO claims VALUES (236, 20, 11, '99214', DATE '2024-04-26', DATE '2024-04-24', 923.00, 1, 'E11.9', 'PAID', DATE '2024-05-10', 923.00);
INSERT INTO claims VALUES (237, 20, 15, '99213', DATE '2024-05-31', DATE '2024-05-29', 567.00, 1, 'M54.5', 'PAID', DATE '2024-06-14', 567.00);
INSERT INTO claims VALUES (238, 20, 19, '99214', DATE '2024-07-05', DATE '2024-07-03', 856.00, 1, 'R10.9', 'PAID', DATE '2024-07-19', 856.00);
INSERT INTO claims VALUES (239, 20, 23, '99213', DATE '2024-08-09', DATE '2024-08-07', 745.00, 1, 'J02.9', 'PAID', DATE '2024-08-23', 745.00);
INSERT INTO claims VALUES (240, 20, 27, '99214', DATE '2024-09-13', DATE '2024-09-11', 890.00, 1, 'E78.5', 'PAID', DATE '2024-09-27', 890.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# --- Pattern B: Statistical Outliers (provider 15) ---
# Provider 15 submits 99214 at $650-$900 (base rate is $130)
echo "Inserting fraudulent claims - Pattern B (Statistical outliers)..."
oracle_query "INSERT INTO claims VALUES (241, 15, 1, '99214', DATE '2024-01-12', DATE '2024-01-10', 128.00, 1, 'I10', 'PAID', DATE '2024-01-26', 128.00);
INSERT INTO claims VALUES (242, 15, 5, '99214', DATE '2024-02-09', DATE '2024-02-07', 135.00, 1, 'E11.9', 'PAID', DATE '2024-02-23', 135.00);
INSERT INTO claims VALUES (243, 15, 9, '99214', DATE '2024-03-08', DATE '2024-03-06', 131.00, 1, 'I10', 'PAID', DATE '2024-03-22', 131.00);
INSERT INTO claims VALUES (244, 15, 13, '99214', DATE '2024-04-05', DATE '2024-04-03', 129.00, 1, 'E78.5', 'PAID', DATE '2024-04-19', 129.00);
INSERT INTO claims VALUES (245, 15, 17, '99214', DATE '2024-05-03', DATE '2024-05-01', 133.00, 1, 'M79.3', 'PAID', DATE '2024-05-17', 133.00);
INSERT INTO claims VALUES (246, 15, 21, '99214', DATE '2024-05-31', DATE '2024-05-29', 127.00, 1, 'E11.65', 'PAID', DATE '2024-06-14', 127.00);
INSERT INTO claims VALUES (247, 15, 25, '99214', DATE '2024-06-28', DATE '2024-06-26', 134.00, 1, 'I10', 'PAID', DATE '2024-07-12', 134.00);
INSERT INTO claims VALUES (248, 15, 29, '99214', DATE '2024-07-26', DATE '2024-07-24', 130.00, 1, 'N39.0', 'PAID', DATE '2024-08-09', 130.00);
INSERT INTO claims VALUES (249, 15, 33, '99214', DATE '2024-08-23', DATE '2024-08-21', 132.00, 1, 'J06.9', 'PAID', DATE '2024-09-06', 132.00);
INSERT INTO claims VALUES (250, 15, 37, '99214', DATE '2024-09-20', DATE '2024-09-18', 136.00, 1, 'E11.9', 'PAID', DATE '2024-10-04', 136.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# Now the outlier claims from provider 15 (4-7x the base rate)
oracle_query "INSERT INTO claims VALUES (251, 15, 2, '99214', DATE '2024-03-15', DATE '2024-03-13', 750.00, 1, 'I10', 'PAID', DATE '2024-03-29', 750.00);
INSERT INTO claims VALUES (252, 15, 6, '99214', DATE '2024-04-12', DATE '2024-04-10', 825.00, 1, 'E11.9', 'PAID', DATE '2024-04-26', 825.00);
INSERT INTO claims VALUES (253, 15, 10, '99214', DATE '2024-05-10', DATE '2024-05-08', 680.00, 1, 'M79.3', 'PAID', DATE '2024-05-24', 680.00);
INSERT INTO claims VALUES (254, 15, 14, '99214', DATE '2024-06-07', DATE '2024-06-05', 790.00, 1, 'E78.5', 'PAID', DATE '2024-06-21', 790.00);
INSERT INTO claims VALUES (255, 15, 18, '99214', DATE '2024-07-05', DATE '2024-07-03', 900.00, 1, 'I10', 'PAID', DATE '2024-07-19', 900.00);
INSERT INTO claims VALUES (256, 15, 22, '99214', DATE '2024-08-02', DATE '2024-07-31', 850.00, 1, 'N39.0', 'PAID', DATE '2024-08-16', 850.00);
INSERT INTO claims VALUES (257, 15, 26, '99214', DATE '2024-09-06', DATE '2024-09-04', 720.00, 1, 'E11.65', 'PAID', DATE '2024-09-20', 720.00);
INSERT INTO claims VALUES (258, 15, 30, '99214', DATE '2024-10-04', DATE '2024-10-02', 775.00, 1, 'J06.9', 'PAID', DATE '2024-10-18', 775.00);
INSERT INTO claims VALUES (259, 15, 34, '99214', DATE '2024-10-25', DATE '2024-10-23', 650.00, 1, 'M54.5', 'PAID', DATE '2024-11-08', 650.00);
INSERT INTO claims VALUES (260, 15, 38, '99214', DATE '2024-11-15', DATE '2024-11-13', 870.00, 1, 'E11.9', 'PAID', DATE '2024-11-29', 870.00);
INSERT INTO claims VALUES (261, 15, 42, '99214', DATE '2024-11-29', DATE '2024-11-27', 695.00, 1, 'I10', 'PAID', DATE '2024-12-13', 695.00);
INSERT INTO claims VALUES (262, 15, 46, '99214', DATE '2024-12-13', DATE '2024-12-11', 810.00, 1, 'R05.9', 'PAID', DATE '2024-12-27', 810.00);
INSERT INTO claims VALUES (263, 15, 50, '99214', DATE '2024-12-20', DATE '2024-12-18', 740.00, 1, 'E78.5', 'PAID', DATE '2025-01-03', 740.00);
INSERT INTO claims VALUES (264, 15, 4, '99214', DATE '2024-12-27', DATE '2024-12-24', 885.00, 1, 'M79.3', 'PAID', DATE '2025-01-10', 885.00);
INSERT INTO claims VALUES (265, 15, 8, '99214', DATE '2024-11-01', DATE '2024-10-30', 660.00, 1, 'N39.0', 'PAID', DATE '2024-11-15', 660.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# --- Pattern C: Duplicate Claims (providers 10-12) ---
# Same patient, same procedure, same/near service date, different claim IDs
echo "Inserting fraudulent claims - Pattern C (Duplicate claims)..."
oracle_query "INSERT INTO claims VALUES (266, 10, 5, '99214', DATE '2024-03-15', DATE '2024-03-15', 130.00, 1, 'I10', 'PAID', DATE '2024-03-29', 130.00);
INSERT INTO claims VALUES (267, 10, 5, '99214', DATE '2024-03-18', DATE '2024-03-15', 130.00, 1, 'I10', 'PAID', DATE '2024-04-01', 130.00);
INSERT INTO claims VALUES (268, 10, 9, '99213', DATE '2024-04-20', DATE '2024-04-20', 92.00, 1, 'J06.9', 'PAID', DATE '2024-05-04', 92.00);
INSERT INTO claims VALUES (269, 10, 9, '99213', DATE '2024-04-22', DATE '2024-04-20', 92.00, 1, 'J06.9', 'PAID', DATE '2024-05-06', 92.00);
INSERT INTO claims VALUES (270, 10, 15, '99214', DATE '2024-06-10', DATE '2024-06-10', 135.00, 1, 'E11.9', 'PAID', DATE '2024-06-24', 135.00);
INSERT INTO claims VALUES (271, 10, 15, '99214', DATE '2024-06-12', DATE '2024-06-10', 135.00, 1, 'E11.9', 'PAID', DATE '2024-06-26', 135.00);
INSERT INTO claims VALUES (272, 10, 22, '99213', DATE '2024-08-05', DATE '2024-08-05', 94.00, 1, 'M54.5', 'PAID', DATE '2024-08-19', 94.00);
INSERT INTO claims VALUES (273, 10, 22, '99213', DATE '2024-08-07', DATE '2024-08-05', 94.00, 1, 'M54.5', 'PAID', DATE '2024-08-21', 94.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

oracle_query "INSERT INTO claims VALUES (274, 11, 3, '99214', DATE '2024-02-20', DATE '2024-02-20', 128.00, 1, 'E78.5', 'PAID', DATE '2024-03-05', 128.00);
INSERT INTO claims VALUES (275, 11, 3, '99214', DATE '2024-02-22', DATE '2024-02-20', 128.00, 1, 'E78.5', 'PAID', DATE '2024-03-07', 128.00);
INSERT INTO claims VALUES (276, 11, 12, '99213', DATE '2024-05-15', DATE '2024-05-15', 91.00, 1, 'J06.9', 'PAID', DATE '2024-05-29', 91.00);
INSERT INTO claims VALUES (277, 11, 12, '99213', DATE '2024-05-17', DATE '2024-05-15', 91.00, 1, 'J06.9', 'PAID', DATE '2024-05-31', 91.00);
INSERT INTO claims VALUES (278, 11, 28, '99214', DATE '2024-07-22', DATE '2024-07-22', 133.00, 1, 'I10', 'PAID', DATE '2024-08-05', 133.00);
INSERT INTO claims VALUES (279, 11, 28, '99214', DATE '2024-07-24', DATE '2024-07-22', 133.00, 1, 'I10', 'PAID', DATE '2024-08-07', 133.00);
INSERT INTO claims VALUES (280, 11, 35, '99213', DATE '2024-09-16', DATE '2024-09-16', 89.00, 1, 'R10.9', 'PAID', DATE '2024-09-30', 89.00);
INSERT INTO claims VALUES (281, 11, 35, '99213', DATE '2024-09-18', DATE '2024-09-16', 89.00, 1, 'R10.9', 'PAID', DATE '2024-10-02', 89.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

oracle_query "INSERT INTO claims VALUES (282, 12, 7, '99214', DATE '2024-04-08', DATE '2024-04-08', 131.00, 1, 'E11.9', 'PAID', DATE '2024-04-22', 131.00);
INSERT INTO claims VALUES (283, 12, 7, '99214', DATE '2024-04-10', DATE '2024-04-08', 131.00, 1, 'E11.9', 'PAID', DATE '2024-04-24', 131.00);
INSERT INTO claims VALUES (284, 12, 18, '99213', DATE '2024-06-17', DATE '2024-06-17', 95.00, 1, 'M54.5', 'PAID', DATE '2024-07-01', 95.00);
INSERT INTO claims VALUES (285, 12, 18, '99213', DATE '2024-06-19', DATE '2024-06-17', 95.00, 1, 'M54.5', 'PAID', DATE '2024-07-03', 95.00);
INSERT INTO claims VALUES (286, 12, 30, '99214', DATE '2024-08-26', DATE '2024-08-26', 136.00, 1, 'I10', 'PAID', DATE '2024-09-09', 136.00);
INSERT INTO claims VALUES (287, 12, 30, '99214', DATE '2024-08-28', DATE '2024-08-26', 136.00, 1, 'I10', 'PAID', DATE '2024-09-11', 136.00);
INSERT INTO claims VALUES (288, 12, 40, '99213', DATE '2024-10-14', DATE '2024-10-14', 90.00, 1, 'J06.9', 'PAID', DATE '2024-10-28', 90.00);
INSERT INTO claims VALUES (289, 12, 40, '99213', DATE '2024-10-16', DATE '2024-10-14', 90.00, 1, 'J06.9', 'PAID', DATE '2024-10-30', 90.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# --- Pattern D: Upcoding (providers 16-17) ---
# These providers submit 80%+ of office visits as 99215 (highest level)
echo "Inserting fraudulent claims - Pattern D (Upcoding)..."
oracle_query "INSERT INTO claims VALUES (290, 16, 2, '99215', DATE '2024-01-19', DATE '2024-01-17', 175.00, 1, 'J06.9', 'PAID', DATE '2024-02-02', 175.00);
INSERT INTO claims VALUES (291, 16, 6, '99215', DATE '2024-02-16', DATE '2024-02-14', 180.00, 1, 'I10', 'PAID', DATE '2024-03-01', 180.00);
INSERT INTO claims VALUES (292, 16, 10, '99215', DATE '2024-03-15', DATE '2024-03-13', 172.00, 1, 'E11.9', 'PAID', DATE '2024-03-29', 172.00);
INSERT INTO claims VALUES (293, 16, 14, '99215', DATE '2024-04-12', DATE '2024-04-10', 178.00, 1, 'M54.5', 'PAID', DATE '2024-04-26', 178.00);
INSERT INTO claims VALUES (294, 16, 18, '99215', DATE '2024-05-10', DATE '2024-05-08', 176.00, 1, 'E78.5', 'PAID', DATE '2024-05-24', 176.00);
INSERT INTO claims VALUES (295, 16, 22, '99215', DATE '2024-06-07', DATE '2024-06-05', 182.00, 1, 'R05.9', 'PAID', DATE '2024-06-21', 182.00);
INSERT INTO claims VALUES (296, 16, 26, '99215', DATE '2024-07-05', DATE '2024-07-03', 170.00, 1, 'I10', 'PAID', DATE '2024-07-19', 170.00);
INSERT INTO claims VALUES (297, 16, 30, '99215', DATE '2024-08-02', DATE '2024-07-31', 177.00, 1, 'N39.0', 'PAID', DATE '2024-08-16', 177.00);
INSERT INTO claims VALUES (298, 16, 34, '99215', DATE '2024-09-06', DATE '2024-09-04', 174.00, 1, 'E11.9', 'PAID', DATE '2024-09-20', 174.00);
INSERT INTO claims VALUES (299, 16, 38, '99213', DATE '2024-10-04', DATE '2024-10-02', 93.00, 1, 'J06.9', 'PAID', DATE '2024-10-18', 93.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

oracle_query "INSERT INTO claims VALUES (300, 17, 4, '99215', DATE '2024-01-26', DATE '2024-01-24', 179.00, 1, 'E11.9', 'PAID', DATE '2024-02-09', 179.00);
INSERT INTO claims VALUES (301, 17, 8, '99215', DATE '2024-02-23', DATE '2024-02-21', 173.00, 1, 'I10', 'PAID', DATE '2024-03-08', 173.00);
INSERT INTO claims VALUES (302, 17, 12, '99215', DATE '2024-03-22', DATE '2024-03-20', 181.00, 1, 'M79.3', 'PAID', DATE '2024-04-05', 181.00);
INSERT INTO claims VALUES (303, 17, 16, '99215', DATE '2024-04-19', DATE '2024-04-17', 176.00, 1, 'J06.9', 'PAID', DATE '2024-05-03', 176.00);
INSERT INTO claims VALUES (304, 17, 20, '99215', DATE '2024-05-17', DATE '2024-05-15', 178.00, 1, 'E78.5', 'PAID', DATE '2024-05-31', 178.00);
INSERT INTO claims VALUES (305, 17, 24, '99215', DATE '2024-06-14', DATE '2024-06-12', 174.00, 1, 'R10.9', 'PAID', DATE '2024-06-28', 174.00);
INSERT INTO claims VALUES (306, 17, 28, '99215', DATE '2024-07-12', DATE '2024-07-10', 180.00, 1, 'I10', 'PAID', DATE '2024-07-26', 180.00);
INSERT INTO claims VALUES (307, 17, 32, '99215', DATE '2024-08-09', DATE '2024-08-07', 175.00, 1, 'M54.5', 'PAID', DATE '2024-08-23', 175.00);
INSERT INTO claims VALUES (308, 17, 36, '99215', DATE '2024-09-06', DATE '2024-09-04', 177.00, 1, 'N39.0', 'PAID', DATE '2024-09-20', 177.00);
INSERT INTO claims VALUES (309, 17, 40, '99214', DATE '2024-10-04', DATE '2024-10-02', 130.00, 1, 'E11.9', 'PAID', DATE '2024-10-18', 130.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# --- Pattern E: Temporal Clustering (provider 13) ---
# 16 claims all on the same date (2024-06-15, a Saturday)
echo "Inserting fraudulent claims - Pattern E (Temporal clustering)..."
oracle_query "INSERT INTO claims VALUES (310, 13, 1, '99213', DATE '2024-06-17', DATE '2024-06-15', 92.00, 1, 'J06.9', 'PAID', DATE '2024-07-01', 92.00);
INSERT INTO claims VALUES (311, 13, 3, '99214', DATE '2024-06-17', DATE '2024-06-15', 130.00, 1, 'I10', 'PAID', DATE '2024-07-01', 130.00);
INSERT INTO claims VALUES (312, 13, 5, '99213', DATE '2024-06-17', DATE '2024-06-15', 94.00, 1, 'E11.9', 'PAID', DATE '2024-07-01', 94.00);
INSERT INTO claims VALUES (313, 13, 7, '99214', DATE '2024-06-17', DATE '2024-06-15', 128.00, 1, 'M54.5', 'PAID', DATE '2024-07-01', 128.00);
INSERT INTO claims VALUES (314, 13, 9, '99213', DATE '2024-06-17', DATE '2024-06-15', 91.00, 1, 'R05.9', 'PAID', DATE '2024-07-01', 91.00);
INSERT INTO claims VALUES (315, 13, 11, '99214', DATE '2024-06-17', DATE '2024-06-15', 135.00, 1, 'E78.5', 'PAID', DATE '2024-07-01', 135.00);
INSERT INTO claims VALUES (316, 13, 13, '99213', DATE '2024-06-17', DATE '2024-06-15', 88.00, 1, 'J02.9', 'PAID', DATE '2024-07-01', 88.00);
INSERT INTO claims VALUES (317, 13, 15, '99214', DATE '2024-06-17', DATE '2024-06-15', 133.00, 1, 'I10', 'PAID', DATE '2024-07-01', 133.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

oracle_query "INSERT INTO claims VALUES (318, 13, 17, '99213', DATE '2024-06-17', DATE '2024-06-15', 95.00, 1, 'N39.0', 'PAID', DATE '2024-07-01', 95.00);
INSERT INTO claims VALUES (319, 13, 19, '99214', DATE '2024-06-17', DATE '2024-06-15', 131.00, 1, 'E11.65', 'PAID', DATE '2024-07-01', 131.00);
INSERT INTO claims VALUES (320, 13, 21, '99213', DATE '2024-06-17', DATE '2024-06-15', 90.00, 1, 'M79.3', 'PAID', DATE '2024-07-01', 90.00);
INSERT INTO claims VALUES (321, 13, 23, '99214', DATE '2024-06-17', DATE '2024-06-15', 134.00, 1, 'J06.9', 'PAID', DATE '2024-07-01', 134.00);
INSERT INTO claims VALUES (322, 13, 25, '99213', DATE '2024-06-17', DATE '2024-06-15', 93.00, 1, 'R10.9', 'PAID', DATE '2024-07-01', 93.00);
INSERT INTO claims VALUES (323, 13, 27, '99214', DATE '2024-06-17', DATE '2024-06-15', 129.00, 1, 'E11.9', 'PAID', DATE '2024-07-01', 129.00);
INSERT INTO claims VALUES (324, 13, 29, '99213', DATE '2024-06-17', DATE '2024-06-15', 96.00, 1, 'I10', 'PAID', DATE '2024-07-01', 96.00);
INSERT INTO claims VALUES (325, 13, 31, '99214', DATE '2024-06-17', DATE '2024-06-15', 132.00, 1, 'M54.5', 'PAID', DATE '2024-07-01', 132.00);
COMMIT;
EXIT;" "claims_analyst" "Claims2024"

# ============================================================
# CREATE FRAUD DETECTION SPECIFICATION FILE
# ============================================================
echo "Creating fraud detection specification file..."
sudo -u ga mkdir -p /home/ga/Desktop 2>/dev/null || mkdir -p /home/ga/Desktop 2>/dev/null || true

cat > /home/ga/Desktop/fraud_detection_spec.txt << 'SPEC'
========================================
FRAUD DETECTION SPECIFICATION v2.1
Insurance Claims Analysis Division
========================================

1. BENFORD'S LAW ANALYSIS
-------------------------
Apply Benford's Law to the first digit of all claim amounts.
Expected first-digit distribution:
  Digit 1: 30.1%
  Digit 2: 17.6%
  Digit 3: 12.5%
  Digit 4: 9.7%
  Digit 5: 7.9%
  Digit 6: 6.7%
  Digit 7: 5.8%
  Digit 8: 5.1%
  Digit 9: 4.6%

Calculate chi-square statistic per provider.
Flag providers where chi-square > 15.51 (critical value, df=8, alpha=0.05).
Flag type: 'BENFORDS_LAW', Severity: 'HIGH'

2. STATISTICAL OUTLIER DETECTION
---------------------------------
For each provider and procedure code combination:
  - Calculate mean and standard deviation of claim amounts
  - Flag individual claims where amount > mean + 3*stddev
  - Minimum 5 claims required for statistical validity
Flag type: 'STATISTICAL_OUTLIER', Severity: 'HIGH'

3. DUPLICATE CLAIM DETECTION
----------------------------
Identify claims where:
  - Same patient_id AND same procedure_code AND
  - service_date within 7 days of another claim
  - Both claims have status != 'DENIED'
Flag type: 'DUPLICATE_CLAIM', Severity: 'CRITICAL'

4. UPCODING DETECTION
----------------------
For E&M Office visit codes (99213, 99214, 99215):
  - Calculate each provider's distribution across these codes
  - Calculate population-wide distribution
  - Flag providers where 99215 usage > population_avg + 2*population_stddev
Flag type: 'UPCODING', Severity: 'MEDIUM'

5. TEMPORAL CLUSTERING
----------------------
Flag providers with more than 12 claims on any single calendar date.
Flag type: 'TEMPORAL_CLUSTER', Severity: 'MEDIUM'

IMPLEMENTATION REQUIREMENTS:
- Use a PL/SQL package called FRAUD_DETECTION_PKG
- Benford's Law analysis must use a pipelined table function
- All flags must be inserted into the FRAUD_FLAGS table
- Create a materialized view FRAUD_SUMMARY_MV for reporting
- Export results to /home/ga/fraud_report.csv
SPEC

chown ga:ga /home/ga/Desktop/fraud_detection_spec.txt 2>/dev/null || true

# ============================================================
# VERIFY DATA INTEGRITY
# ============================================================
echo "Verifying data integrity..."

PROVIDER_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM providers;" "claims_analyst" | tr -d '[:space:]')
PATIENT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM patients;" "claims_analyst" | tr -d '[:space:]')
PROC_CODE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM procedure_codes;" "claims_analyst" | tr -d '[:space:]')
CLAIM_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM claims;" "claims_analyst" | tr -d '[:space:]')

echo "Data loaded: providers=$PROVIDER_COUNT, patients=$PATIENT_COUNT, procedure_codes=$PROC_CODE_COUNT, claims=$CLAIM_COUNT"

# Record baseline counts
printf '%s' "${PROVIDER_COUNT:-20}" > /tmp/initial_provider_count
printf '%s' "${PATIENT_COUNT:-50}" > /tmp/initial_patient_count
printf '%s' "${CLAIM_COUNT:-325}" > /tmp/initial_claim_count

# ============================================================
# CONFIGURE SQL DEVELOPER CONNECTION
# ============================================================
echo "Configuring SQL Developer connection..."

SQLDEVELOPER_SYSTEM_DIR=$(find /home/ga/.sqldeveloper -maxdepth 1 -name "system*" -type d 2>/dev/null | head -1)
if [ -n "$SQLDEVELOPER_SYSTEM_DIR" ]; then
    CONN_DIR=$(find "$SQLDEVELOPER_SYSTEM_DIR" -name "o.jdeveloper.db.connection*" -type d 2>/dev/null | head -1)
    if [ -z "$CONN_DIR" ]; then
        CONN_DIR="$SQLDEVELOPER_SYSTEM_DIR/o.jdeveloper.db.connection.24.2.0.284.2209"
        mkdir -p "$CONN_DIR"
    fi
    CONN_FILE="$CONN_DIR/connections.json"
    cat > "$CONN_FILE" << CONNEOF
{
  "connections": [
    {
      "name": "Claims Database",
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
        "ConnName": "Claims Database",
        "serviceName": "XEPDB1",
        "user": "claims_analyst",
        "password": "Claims2024"
      }
    }
  ]
}
CONNEOF
    chown ga:ga "$CONN_FILE"
    echo "Pre-configured connection 'Claims Database' in $CONN_FILE"
fi

# Ensure SQL Developer is focused
sleep 2
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Take initial screenshot
take_screenshot /tmp/initial_screenshot.png

echo "=== Insurance Claims Fraud Detection setup complete ==="
echo "Schema: claims_analyst/Claims2024"
echo "Tables: PROVIDERS($PROVIDER_COUNT), PATIENTS($PATIENT_COUNT), PROCEDURE_CODES($PROC_CODE_COUNT), CLAIMS($CLAIM_COUNT)"
echo "Fraud patterns embedded: Benford's Law violation (providers 18-20), Statistical outliers (provider 15),"
echo "  Duplicate claims (providers 10-12), Upcoding (providers 16-17), Temporal clustering (provider 13)"
echo "Spec file: /home/ga/Desktop/fraud_detection_spec.txt"
