#!/bin/bash
# Setup script for Energy Portfolio Milestone Tracker task
echo "=== Setting up Energy Portfolio Milestone Tracker ==="

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

# --- Drop and recreate the ENERGY_MGR user cleanly ---
echo "Setting up ENERGY schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER energy_mgr CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER energy_mgr IDENTIFIED BY Energy2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO energy_mgr;
GRANT RESOURCE TO energy_mgr;
GRANT CREATE VIEW TO energy_mgr;
GRANT CREATE PROCEDURE TO energy_mgr;
GRANT CREATE JOB TO energy_mgr;
GRANT CREATE SESSION TO energy_mgr;
GRANT CREATE ANY CONTEXT TO energy_mgr;
GRANT CREATE ANY JOB TO energy_mgr;
EXIT;" "system"

echo "ENERGY_MGR user created with required privileges"

# --- Create tables in ENERGY schema ---
echo "Creating PORTFOLIO table..."
oracle_query "CREATE TABLE energy_mgr.portfolio (
  portfolio_id   NUMBER PRIMARY KEY,
  portfolio_name VARCHAR2(100),
  manager        VARCHAR2(100)
);
EXIT;" "system"

echo "Creating REGIONS table..."
oracle_query "CREATE TABLE energy_mgr.regions (
  region_id    NUMBER PRIMARY KEY,
  region_name  VARCHAR2(100),
  portfolio_id NUMBER REFERENCES energy_mgr.portfolio(portfolio_id)
);
EXIT;" "system"

echo "Creating PROJECTS table..."
oracle_query "CREATE TABLE energy_mgr.projects (
  project_id   NUMBER PRIMARY KEY,
  project_name VARCHAR2(200),
  region_id    NUMBER REFERENCES energy_mgr.regions(region_id),
  capacity_mw  NUMBER(10,2),
  turbine_count NUMBER,
  state        VARCHAR2(50),
  county       VARCHAR2(100),
  latitude     NUMBER(10,6),
  longitude    NUMBER(10,6),
  developer    VARCHAR2(200),
  status       VARCHAR2(30),
  eia_plant_code VARCHAR2(20)
);
EXIT;" "system"

echo "Creating PHASES table..."
oracle_query "CREATE TABLE energy_mgr.phases (
  phase_id    NUMBER PRIMARY KEY,
  project_id  NUMBER REFERENCES energy_mgr.projects(project_id),
  phase_name  VARCHAR2(100),
  phase_order NUMBER,
  start_date  DATE,
  end_date    DATE
);
EXIT;" "system"

echo "Creating MILESTONES table (range partitioned by target_date)..."
oracle_query "CREATE TABLE energy_mgr.milestones (
  milestone_id    NUMBER PRIMARY KEY,
  phase_id        NUMBER,
  project_id      NUMBER,
  milestone_name  VARCHAR2(100),
  milestone_order NUMBER,
  target_date     DATE,
  actual_date     DATE,
  status          VARCHAR2(20) DEFAULT 'NOT_STARTED',
  notes           VARCHAR2(500),
  CONSTRAINT fk_ms_phase FOREIGN KEY (phase_id) REFERENCES energy_mgr.phases(phase_id),
  CONSTRAINT fk_ms_project FOREIGN KEY (project_id) REFERENCES energy_mgr.projects(project_id)
)
PARTITION BY RANGE (target_date) (
  PARTITION p_2022_q1 VALUES LESS THAN (DATE '2022-04-01'),
  PARTITION p_2022_q2 VALUES LESS THAN (DATE '2022-07-01'),
  PARTITION p_2022_q3 VALUES LESS THAN (DATE '2022-10-01'),
  PARTITION p_2022_q4 VALUES LESS THAN (DATE '2023-01-01'),
  PARTITION p_2023_q1 VALUES LESS THAN (DATE '2023-04-01'),
  PARTITION p_2023_q2 VALUES LESS THAN (DATE '2023-07-01'),
  PARTITION p_2023_q3 VALUES LESS THAN (DATE '2023-10-01'),
  PARTITION p_2023_q4 VALUES LESS THAN (DATE '2024-01-01'),
  PARTITION p_2024_q1 VALUES LESS THAN (DATE '2024-04-01'),
  PARTITION p_2024_q2 VALUES LESS THAN (DATE '2024-07-01'),
  PARTITION p_2024_q3 VALUES LESS THAN (DATE '2024-10-01'),
  PARTITION p_2024_q4 VALUES LESS THAN (DATE '2025-01-01'),
  PARTITION p_2025_q1 VALUES LESS THAN (DATE '2025-04-01'),
  PARTITION p_2025_q2 VALUES LESS THAN (DATE '2025-07-01'),
  PARTITION p_2025_q3 VALUES LESS THAN (DATE '2025-10-01'),
  PARTITION p_2025_q4 VALUES LESS THAN (DATE '2026-01-01')
);
EXIT;" "system"

echo "Creating ALERTS table..."
oracle_query "CREATE TABLE energy_mgr.alerts (
  alert_id       NUMBER PRIMARY KEY,
  project_id     NUMBER,
  milestone_id   NUMBER,
  alert_type     VARCHAR2(50),
  alert_message  VARCHAR2(500),
  created_date   DATE DEFAULT SYSDATE,
  acknowledged   NUMBER(1) DEFAULT 0
);
EXIT;" "system"

# --- Create sequences ---
echo "Creating sequences..."
oracle_query "CREATE SEQUENCE energy_mgr.portfolio_seq START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE energy_mgr.region_seq START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE energy_mgr.project_seq START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE energy_mgr.phase_seq START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE energy_mgr.milestone_seq START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE energy_mgr.alert_seq START WITH 1 INCREMENT BY 1;
EXIT;" "system"

# --- Insert Portfolio data ---
echo "Inserting portfolio data..."
oracle_query "INSERT INTO energy_mgr.portfolio VALUES (1, 'North American Wind Portfolio', 'Energy Management Group');
COMMIT;
EXIT;" "system"

# --- Insert Regions ---
echo "Inserting region data..."
oracle_query "INSERT INTO energy_mgr.regions VALUES (1, 'Pacific Northwest', 1);
INSERT INTO energy_mgr.regions VALUES (2, 'California', 1);
INSERT INTO energy_mgr.regions VALUES (3, 'Texas', 1);
INSERT INTO energy_mgr.regions VALUES (4, 'Great Plains', 1);
COMMIT;
EXIT;" "system"

# --- Insert REAL wind farm projects from EIA-860 database ---
echo "Inserting wind farm project data (EIA-860)..."

# Region 1: Pacific Northwest
oracle_query "INSERT INTO energy_mgr.projects VALUES (1, 'Shepherds Flat', 1, 845.00, 338, 'Oregon', 'Gilliam County', 45.558300, -120.116700, 'Caithness Energy', 'ACTIVE', '57206');
INSERT INTO energy_mgr.projects VALUES (2, 'Biglow Canyon', 1, 450.00, 217, 'Oregon', 'Sherman County', 45.590000, -120.840000, 'Portland General Electric', 'ACTIVE', NULL);
COMMIT;
EXIT;" "system"

# Region 2: California
oracle_query "INSERT INTO energy_mgr.projects VALUES (3, 'Alta Wind Energy Center', 2, 1548.00, 600, 'California', 'Kern County', 35.083300, -118.366700, 'Terra-Gen', 'ACTIVE', NULL);
INSERT INTO energy_mgr.projects VALUES (4, 'San Gorgonio Pass', 2, 615.00, 2700, 'California', 'Riverside County', 33.916700, -116.583300, 'Various', 'ACTIVE', NULL);
COMMIT;
EXIT;" "system"

# Region 3: Texas
oracle_query "INSERT INTO energy_mgr.projects VALUES (5, 'Roscoe Wind Farm', 3, 781.50, 627, 'Texas', 'Nolan County', 32.450000, -100.533300, 'E.ON Climate', 'ACTIVE', NULL);
INSERT INTO energy_mgr.projects VALUES (6, 'Horse Hollow Wind Energy Center', 3, 735.50, 421, 'Texas', 'Taylor County', 32.183300, -100.050000, 'NextEra Energy', 'ACTIVE', NULL);
COMMIT;
EXIT;" "system"

# Region 4: Great Plains
oracle_query "INSERT INTO energy_mgr.projects VALUES (7, 'Meadow Lake Wind Farm', 4, 801.00, 414, 'Indiana', 'White County', 40.683300, -86.883300, 'EDP Renewables', 'ACTIVE', NULL);
INSERT INTO energy_mgr.projects VALUES (8, 'Fowler Ridge Wind Farm', 4, 750.00, 355, 'Indiana', 'Benton County', 40.533300, -87.383300, 'BP Wind Energy', 'ACTIVE', NULL);
COMMIT;
EXIT;" "system"

# --- Insert 4 phases per project ---
echo "Inserting project phases..."
oracle_query "DECLARE
  v_phase_id NUMBER := 1;
BEGIN
  FOR proj IN (SELECT project_id FROM energy_mgr.projects ORDER BY project_id) LOOP
    INSERT INTO energy_mgr.phases VALUES (v_phase_id, proj.project_id, 'Development', 1,
      DATE '2022-01-01' + (proj.project_id - 1) * 30,
      DATE '2022-06-30' + (proj.project_id - 1) * 30);
    v_phase_id := v_phase_id + 1;

    INSERT INTO energy_mgr.phases VALUES (v_phase_id, proj.project_id, 'Construction', 2,
      DATE '2022-07-01' + (proj.project_id - 1) * 30,
      DATE '2023-06-30' + (proj.project_id - 1) * 30);
    v_phase_id := v_phase_id + 1;

    INSERT INTO energy_mgr.phases VALUES (v_phase_id, proj.project_id, 'Commissioning', 3,
      DATE '2023-07-01' + (proj.project_id - 1) * 30,
      DATE '2023-12-31' + (proj.project_id - 1) * 30);
    v_phase_id := v_phase_id + 1;

    INSERT INTO energy_mgr.phases VALUES (v_phase_id, proj.project_id, 'Operations', 4,
      DATE '2024-01-01' + (proj.project_id - 1) * 30,
      NULL);
    v_phase_id := v_phase_id + 1;
  END LOOP;
  COMMIT;
END;
/
EXIT;" "system"

# --- Insert milestones for CORRECTLY sequenced projects ---
# Correctly sequenced: Biglow Canyon (2), San Gorgonio (4), Meadow Lake (7), Fowler Ridge (8)
echo "Inserting milestones for correctly sequenced projects..."

# Helper: phase_id for a project = (project_id - 1) * 4 + phase_order
# Milestone mapping to phases:
#   milestones 1-2 (Site Assessment, Environmental Review) -> Development phase (phase_order=1)
#   milestones 3-4 (Permitting Approved, Financial Close) -> Development phase (phase_order=1)
#   milestones 5-7 (Construction Start, Grid Interconnection, Construction Complete) -> Construction phase (phase_order=2)
#   milestone 8 (Commercial Operation) -> Commissioning phase (phase_order=3)

# Biglow Canyon (project_id=2) - phases: 5,6,7,8
oracle_query "INSERT INTO energy_mgr.milestones VALUES (9, 5, 2, 'Site Assessment', 1, DATE '2022-02-15', DATE '2022-02-10', 'COMPLETED', 'Comprehensive wind resource assessment completed');
INSERT INTO energy_mgr.milestones VALUES (10, 5, 2, 'Environmental Review', 2, DATE '2022-05-01', DATE '2022-04-28', 'COMPLETED', 'NEPA review and wildlife impact study passed');
INSERT INTO energy_mgr.milestones VALUES (11, 5, 2, 'Permitting Approved', 3, DATE '2022-08-15', DATE '2022-08-10', 'COMPLETED', 'State and county permits secured');
INSERT INTO energy_mgr.milestones VALUES (12, 5, 2, 'Financial Close', 4, DATE '2022-11-01', DATE '2022-10-25', 'COMPLETED', 'PPA executed with Portland General Electric');
INSERT INTO energy_mgr.milestones VALUES (13, 6, 2, 'Construction Start', 5, DATE '2023-02-01', DATE '2023-01-28', 'COMPLETED', 'Ground breaking ceremony completed');
INSERT INTO energy_mgr.milestones VALUES (14, 6, 2, 'Grid Interconnection', 6, DATE '2023-06-15', DATE '2023-06-10', 'COMPLETED', 'BPA interconnection agreement activated');
INSERT INTO energy_mgr.milestones VALUES (15, 6, 2, 'Construction Complete', 7, DATE '2023-10-01', DATE '2023-09-28', 'COMPLETED', 'All 217 turbines installed and tested');
INSERT INTO energy_mgr.milestones VALUES (16, 7, 2, 'Commercial Operation', 8, DATE '2024-01-15', DATE '2024-01-10', 'COMPLETED', 'Full commercial operations commenced');
COMMIT;
EXIT;" "system"

# San Gorgonio Pass (project_id=4) - phases: 13,14,15,16
oracle_query "INSERT INTO energy_mgr.milestones VALUES (25, 13, 4, 'Site Assessment', 1, DATE '2022-03-01', DATE '2022-02-25', 'COMPLETED', 'Wind measurement campaign concluded');
INSERT INTO energy_mgr.milestones VALUES (26, 13, 4, 'Environmental Review', 2, DATE '2022-06-01', DATE '2022-05-20', 'COMPLETED', 'Desert tortoise habitat mitigation plan approved');
INSERT INTO energy_mgr.milestones VALUES (27, 13, 4, 'Permitting Approved', 3, DATE '2022-09-15', DATE '2022-09-10', 'COMPLETED', 'Riverside County CUP granted');
INSERT INTO energy_mgr.milestones VALUES (28, 13, 4, 'Financial Close', 4, DATE '2022-12-01', DATE '2022-11-28', 'COMPLETED', 'Tax equity financing secured');
INSERT INTO energy_mgr.milestones VALUES (29, 14, 4, 'Construction Start', 5, DATE '2023-03-01', DATE '2023-02-20', 'COMPLETED', 'Phase 1 repowering initiated');
INSERT INTO energy_mgr.milestones VALUES (30, 14, 4, 'Grid Interconnection', 6, DATE '2023-07-15', DATE '2023-07-10', 'COMPLETED', 'SCE interconnection completed');
INSERT INTO energy_mgr.milestones VALUES (31, 14, 4, 'Construction Complete', 7, DATE '2023-11-01', DATE '2023-11-15', 'COMPLETED', 'Repowering of 2700 turbines complete');
INSERT INTO energy_mgr.milestones VALUES (32, 15, 4, 'Commercial Operation', 8, DATE '2024-02-15', DATE '2024-02-20', 'COMPLETED', 'Full 615MW capacity online');
COMMIT;
EXIT;" "system"

# Meadow Lake (project_id=7) - phases: 25,26,27,28
oracle_query "INSERT INTO energy_mgr.milestones VALUES (49, 25, 7, 'Site Assessment', 1, DATE '2022-03-15', DATE '2022-03-10', 'COMPLETED', 'Indiana wind resource validated');
INSERT INTO energy_mgr.milestones VALUES (50, 25, 7, 'Environmental Review', 2, DATE '2022-06-15', DATE '2022-06-12', 'COMPLETED', 'USFWS eagle take permit obtained');
INSERT INTO energy_mgr.milestones VALUES (51, 25, 7, 'Permitting Approved', 3, DATE '2022-09-01', DATE '2022-08-28', 'COMPLETED', 'White County zoning approved');
INSERT INTO energy_mgr.milestones VALUES (52, 25, 7, 'Financial Close', 4, DATE '2022-12-15', DATE '2022-12-10', 'COMPLETED', 'EDP Renewables project financing closed');
INSERT INTO energy_mgr.milestones VALUES (53, 26, 7, 'Construction Start', 5, DATE '2023-03-15', DATE '2023-03-12', 'COMPLETED', 'Foundation pouring commenced');
INSERT INTO energy_mgr.milestones VALUES (54, 26, 7, 'Grid Interconnection', 6, DATE '2023-07-01', DATE '2023-06-28', 'COMPLETED', 'MISO interconnection agreement executed');
INSERT INTO energy_mgr.milestones VALUES (55, 26, 7, 'Construction Complete', 7, DATE '2023-11-15', DATE '2023-11-20', 'COMPLETED', 'All 414 turbines operational');
INSERT INTO energy_mgr.milestones VALUES (56, 27, 7, 'Commercial Operation', 8, DATE '2024-03-01', NULL, 'IN_PROGRESS', 'Final commissioning tests underway');
COMMIT;
EXIT;" "system"

# Fowler Ridge (project_id=8) - phases: 29,30,31,32
oracle_query "INSERT INTO energy_mgr.milestones VALUES (57, 29, 8, 'Site Assessment', 1, DATE '2022-04-01', DATE '2022-03-25', 'COMPLETED', 'Benton County wind study completed');
INSERT INTO energy_mgr.milestones VALUES (58, 29, 8, 'Environmental Review', 2, DATE '2022-07-01', DATE '2022-06-28', 'COMPLETED', 'Avian and bat impact study cleared');
INSERT INTO energy_mgr.milestones VALUES (59, 29, 8, 'Permitting Approved', 3, DATE '2022-10-01', DATE '2022-09-25', 'COMPLETED', 'Benton County BZA approval secured');
INSERT INTO energy_mgr.milestones VALUES (60, 29, 8, 'Financial Close', 4, DATE '2023-01-15', DATE '2023-01-10', 'COMPLETED', 'BP Wind Energy financing finalized');
INSERT INTO energy_mgr.milestones VALUES (61, 30, 8, 'Construction Start', 5, DATE '2023-04-15', DATE '2023-04-12', 'COMPLETED', 'Turbine delivery and installation begun');
INSERT INTO energy_mgr.milestones VALUES (62, 30, 8, 'Grid Interconnection', 6, DATE '2023-08-15', DATE '2023-08-10', 'COMPLETED', 'PJM interconnection study completed');
INSERT INTO energy_mgr.milestones VALUES (63, 30, 8, 'Construction Complete', 7, DATE '2023-12-15', NULL, 'IN_PROGRESS', 'Final turbine commissioning in progress');
INSERT INTO energy_mgr.milestones VALUES (64, 31, 8, 'Commercial Operation', 8, DATE '2024-04-01', NULL, 'NOT_STARTED', 'Awaiting construction completion');
COMMIT;
EXIT;" "system"

# --- Insert milestones for CONTAMINATED projects (with sequence violations) ---
echo "Inserting milestones with SEQUENCE VIOLATIONS for contaminated projects..."

# Shepherds Flat (project_id=1) - phases: 1,2,3,4
# VIOLATION: Construction Complete (milestone 7) actual_date = 2023-03-15
#            BUT Permitting Approved (milestone 3) actual_date = 2023-09-20
# (Construction completed 6 months BEFORE permitting was approved)
oracle_query "INSERT INTO energy_mgr.milestones VALUES (1, 1, 1, 'Site Assessment', 1, DATE '2022-01-15', DATE '2022-01-10', 'COMPLETED', 'Wind resource assessment for Gilliam County');
INSERT INTO energy_mgr.milestones VALUES (2, 1, 1, 'Environmental Review', 2, DATE '2022-04-15', DATE '2022-04-10', 'COMPLETED', 'Environmental impact study cleared');
INSERT INTO energy_mgr.milestones VALUES (3, 1, 1, 'Permitting Approved', 3, DATE '2022-07-15', DATE '2023-09-20', 'COMPLETED', 'Oregon state permits filed');
INSERT INTO energy_mgr.milestones VALUES (4, 1, 1, 'Financial Close', 4, DATE '2022-10-15', DATE '2022-10-10', 'COMPLETED', 'Caithness Energy deal finalized');
INSERT INTO energy_mgr.milestones VALUES (5, 2, 1, 'Construction Start', 5, DATE '2023-01-15', DATE '2023-01-10', 'COMPLETED', 'Foundation work commenced');
INSERT INTO energy_mgr.milestones VALUES (6, 2, 1, 'Grid Interconnection', 6, DATE '2023-05-15', DATE '2023-05-10', 'COMPLETED', 'BPA grid connection established');
INSERT INTO energy_mgr.milestones VALUES (7, 2, 1, 'Construction Complete', 7, DATE '2023-09-15', DATE '2023-03-15', 'COMPLETED', 'All 338 turbines installed');
INSERT INTO energy_mgr.milestones VALUES (8, 3, 1, 'Commercial Operation', 8, DATE '2024-01-01', DATE '2023-12-20', 'COMPLETED', '845MW online');
COMMIT;
EXIT;" "system"

# Alta Wind Energy Center (project_id=3) - phases: 9,10,11,12
# VIOLATION: Commercial Operation (milestone 8) actual_date = 2023-06-01
#            BUT Grid Interconnection (milestone 6) actual_date = 2024-01-15
# (Commercial operation 7 months BEFORE grid interconnection)
oracle_query "INSERT INTO energy_mgr.milestones VALUES (17, 9, 3, 'Site Assessment', 1, DATE '2022-02-01', DATE '2022-01-28', 'COMPLETED', 'Tehachapi wind resource analysis');
INSERT INTO energy_mgr.milestones VALUES (18, 9, 3, 'Environmental Review', 2, DATE '2022-05-15', DATE '2022-05-10', 'COMPLETED', 'Kern County environmental clearance');
INSERT INTO energy_mgr.milestones VALUES (19, 9, 3, 'Permitting Approved', 3, DATE '2022-08-01', DATE '2022-07-28', 'COMPLETED', 'CUP and building permits obtained');
INSERT INTO energy_mgr.milestones VALUES (20, 9, 3, 'Financial Close', 4, DATE '2022-11-15', DATE '2022-11-10', 'COMPLETED', 'Terra-Gen financing agreement signed');
INSERT INTO energy_mgr.milestones VALUES (21, 10, 3, 'Construction Start', 5, DATE '2023-02-15', DATE '2023-02-10', 'COMPLETED', 'Phase 11 construction launched');
INSERT INTO energy_mgr.milestones VALUES (22, 10, 3, 'Grid Interconnection', 6, DATE '2023-06-01', DATE '2024-01-15', 'COMPLETED', 'SCE transmission line upgrade pending');
INSERT INTO energy_mgr.milestones VALUES (23, 10, 3, 'Construction Complete', 7, DATE '2023-10-15', DATE '2023-10-10', 'COMPLETED', '600 turbines across 5 phases installed');
INSERT INTO energy_mgr.milestones VALUES (24, 11, 3, 'Commercial Operation', 8, DATE '2024-02-01', DATE '2023-06-01', 'COMPLETED', '1548MW capacity declared commercial');
COMMIT;
EXIT;" "system"

# Roscoe Wind Farm (project_id=5) - phases: 17,18,19,20
# VIOLATION: Financial Close (milestone 4) actual_date = 2022-11-01
#            BUT Environmental Review (milestone 2) actual_date = 2023-04-15
# (Financing closed before environmental review completed)
oracle_query "INSERT INTO energy_mgr.milestones VALUES (33, 17, 5, 'Site Assessment', 1, DATE '2022-02-15', DATE '2022-02-10', 'COMPLETED', 'Nolan County wind measurements verified');
INSERT INTO energy_mgr.milestones VALUES (34, 17, 5, 'Environmental Review', 2, DATE '2022-05-15', DATE '2023-04-15', 'COMPLETED', 'TCEQ environmental assessment ongoing');
INSERT INTO energy_mgr.milestones VALUES (35, 17, 5, 'Permitting Approved', 3, DATE '2022-08-15', DATE '2022-08-10', 'COMPLETED', 'Nolan County permits approved');
INSERT INTO energy_mgr.milestones VALUES (36, 17, 5, 'Financial Close', 4, DATE '2022-11-15', DATE '2022-11-01', 'COMPLETED', 'E.ON Climate project financing secured');
INSERT INTO energy_mgr.milestones VALUES (37, 18, 5, 'Construction Start', 5, DATE '2023-02-15', DATE '2023-02-10', 'COMPLETED', 'Turbine foundation construction started');
INSERT INTO energy_mgr.milestones VALUES (38, 18, 5, 'Grid Interconnection', 6, DATE '2023-06-15', DATE '2023-06-10', 'COMPLETED', 'ERCOT interconnection completed');
INSERT INTO energy_mgr.milestones VALUES (39, 18, 5, 'Construction Complete', 7, DATE '2023-10-15', DATE '2023-10-10', 'COMPLETED', 'All 627 turbines commissioned');
INSERT INTO energy_mgr.milestones VALUES (40, 19, 5, 'Commercial Operation', 8, DATE '2024-02-01', DATE '2024-01-25', 'COMPLETED', '781.5MW fully operational');
COMMIT;
EXIT;" "system"

# Horse Hollow Wind Energy Center (project_id=6) - phases: 21,22,23,24
# VIOLATION: Grid Interconnection (milestone 6) actual_date = 2023-02-01
#            BUT Construction Start (milestone 5) actual_date = 2023-08-20
# (Grid interconnected before construction even started)
oracle_query "INSERT INTO energy_mgr.milestones VALUES (41, 21, 6, 'Site Assessment', 1, DATE '2022-03-01', DATE '2022-02-25', 'COMPLETED', 'Taylor County wind assessment complete');
INSERT INTO energy_mgr.milestones VALUES (42, 21, 6, 'Environmental Review', 2, DATE '2022-06-01', DATE '2022-05-28', 'COMPLETED', 'USFWS clearance obtained');
INSERT INTO energy_mgr.milestones VALUES (43, 21, 6, 'Permitting Approved', 3, DATE '2022-09-01', DATE '2022-08-25', 'COMPLETED', 'Taylor County development permit issued');
INSERT INTO energy_mgr.milestones VALUES (44, 21, 6, 'Financial Close', 4, DATE '2022-12-01', DATE '2022-11-28', 'COMPLETED', 'NextEra Energy financing completed');
INSERT INTO energy_mgr.milestones VALUES (45, 22, 6, 'Construction Start', 5, DATE '2023-03-01', DATE '2023-08-20', 'COMPLETED', 'Delayed due to supply chain issues');
INSERT INTO energy_mgr.milestones VALUES (46, 22, 6, 'Grid Interconnection', 6, DATE '2023-07-01', DATE '2023-02-01', 'COMPLETED', 'ERCOT grid connection activated');
INSERT INTO energy_mgr.milestones VALUES (47, 22, 6, 'Construction Complete', 7, DATE '2023-11-01', DATE '2023-11-15', 'COMPLETED', '421 turbines erected and tested');
INSERT INTO energy_mgr.milestones VALUES (48, 23, 6, 'Commercial Operation', 8, DATE '2024-03-01', NULL, 'IN_PROGRESS', 'Final testing phase');
COMMIT;
EXIT;" "system"

# --- Grant table ownership to energy_mgr ---
echo "Granting object privileges to energy_mgr..."
oracle_query "GRANT ALL ON energy_mgr.portfolio TO energy_mgr;
GRANT ALL ON energy_mgr.regions TO energy_mgr;
GRANT ALL ON energy_mgr.projects TO energy_mgr;
GRANT ALL ON energy_mgr.phases TO energy_mgr;
GRANT ALL ON energy_mgr.milestones TO energy_mgr;
GRANT ALL ON energy_mgr.alerts TO energy_mgr;
GRANT ALL ON energy_mgr.portfolio_seq TO energy_mgr;
GRANT ALL ON energy_mgr.region_seq TO energy_mgr;
GRANT ALL ON energy_mgr.project_seq TO energy_mgr;
GRANT ALL ON energy_mgr.phase_seq TO energy_mgr;
GRANT ALL ON energy_mgr.milestone_seq TO energy_mgr;
GRANT ALL ON energy_mgr.alert_seq TO energy_mgr;
EXIT;" "system"

# --- Verify data insertion ---
echo "Verifying data..."
PORTFOLIO_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM energy_mgr.portfolio;" "system" | tr -d '[:space:]')
REGION_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM energy_mgr.regions;" "system" | tr -d '[:space:]')
PROJECT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM energy_mgr.projects;" "system" | tr -d '[:space:]')
PHASE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM energy_mgr.phases;" "system" | tr -d '[:space:]')
MILESTONE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM energy_mgr.milestones;" "system" | tr -d '[:space:]')

echo "Data loaded: portfolio=$PORTFOLIO_COUNT, regions=$REGION_COUNT, projects=$PROJECT_COUNT, phases=$PHASE_COUNT, milestones=$MILESTONE_COUNT"

# --- Record baseline state for evaluation ---
echo "Recording baseline state..."
printf '%s' "${MILESTONE_COUNT:-64}" > /tmp/initial_milestone_count
printf '%s' "${PROJECT_COUNT:-8}" > /tmp/initial_project_count

# Count initial sequence violations for verification
VIOLATION_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM (
  SELECT m1.project_id, m1.milestone_name AS earlier_ms, m2.milestone_name AS later_ms
  FROM energy_mgr.milestones m1
  JOIN energy_mgr.milestones m2 ON m1.project_id = m2.project_id
  WHERE m1.milestone_order < m2.milestone_order
    AND m1.actual_date IS NOT NULL
    AND m2.actual_date IS NOT NULL
    AND m1.actual_date > m2.actual_date
);" "system" | tr -d '[:space:]')
printf '%s' "${VIOLATION_COUNT:-0}" > /tmp/initial_violation_count
echo "Baseline: $VIOLATION_COUNT milestone sequence violations detected"

# Ensure export directory exists
sudo -u ga mkdir -p /home/ga/Documents/exports 2>/dev/null || mkdir -p /home/ga/Documents/exports 2>/dev/null || true

# --- Pre-configure SQL Developer connection for energy_mgr ---
echo "Configuring SQL Developer connection..."
SQLDEVELOPER_SYSTEM_DIR=$(find /home/ga/.sqldeveloper -maxdepth 1 -name "system*" -type d 2>/dev/null | head -1)
if [ -n "$SQLDEVELOPER_SYSTEM_DIR" ]; then
    CONN_DIR=$(find "$SQLDEVELOPER_SYSTEM_DIR" -name "o.jdeveloper.db.connection*" -type d 2>/dev/null | head -1)
    if [ -z "$CONN_DIR" ]; then
        CONN_DIR="$SQLDEVELOPER_SYSTEM_DIR/o.jdeveloper.db.connection.24.2.0.284.2209"
        mkdir -p "$CONN_DIR"
    fi
    CONN_FILE="$CONN_DIR/connections.json"
    cat > "$CONN_FILE" << 'CONNEOF'
{
  "connections": [
    {
      "name": "Energy Portfolio DB",
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
        "ConnName": "Energy Portfolio DB",
        "serviceName": "XEPDB1",
        "user": "energy_mgr",
        "password": "Energy2024"
      }
    }
  ]
}
CONNEOF
    chown ga:ga "$CONN_FILE"
    echo "Pre-configured Energy Portfolio DB connection"
fi

sleep 2

# Focus SQL Developer window
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Take initial screenshot
take_screenshot /tmp/energy_portfolio_setup.png

echo "=== Energy Portfolio Milestone Tracker setup complete ==="
echo "ENERGY_MGR schema created with:"
echo "  - 1 portfolio, 4 regions, 8 real wind farm projects (EIA-860 data)"
echo "  - 32 phases (4 per project), 64 milestones (8 per project)"
echo "  - 4 projects with milestone sequence violations (contamination injected)"
echo "  - MILESTONES table partitioned by quarter (2022-2025)"
echo "  - Sequences for auto-incrementing IDs"
echo "  - ALERTS table ready for scheduled job output"
