#!/bin/bash
echo "=== Setting up Geological Drill Hole Compositing Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# 1. Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# 2. Clean up previous artifacts
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER geo_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# 3. Create GEO_ADMIN user
echo "Creating GEO_ADMIN user..."
oracle_query "CREATE USER geo_admin IDENTIFIED BY Geo2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO geo_admin;
GRANT RESOURCE TO geo_admin;
GRANT CREATE VIEW TO geo_admin;
GRANT CREATE PROCEDURE TO geo_admin;
GRANT CREATE SESSION TO geo_admin;
EXIT;" "system"

# 4. Create schema and insert data
echo "Creating tables and inserting geological data..."
sudo docker exec -i oracle-xe sqlplus -s geo_admin/Geo2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE collars (
  hole_id    VARCHAR2(20) PRIMARY KEY,
  easting    NUMBER,
  northing   NUMBER,
  elevation  NUMBER,
  max_depth  NUMBER,
  drill_date DATE
);

CREATE TABLE core_assays (
  assay_id          NUMBER PRIMARY KEY,
  hole_id           VARCHAR2(20) REFERENCES collars(hole_id),
  depth_from        NUMBER,
  depth_to          NUMBER,
  au_gpt            NUMBER,
  ag_gpt            NUMBER,
  core_recovery_pct NUMBER
);

-- H001: Testing Overlap Correction
INSERT INTO collars VALUES ('H001', 500000, 6000000, 400, 50, SYSDATE);
INSERT INTO core_assays VALUES (1, 'H001', 0, 1.5, 0.1, 1.0, 95);
-- Error: depth_from 1.0 overlaps with previous depth_to 1.5 (Correction should make it 1.5 to 3.0)
INSERT INTO core_assays VALUES (2, 'H001', 1.0, 3.0, 0.2, 1.5, 90); 
INSERT INTO core_assays VALUES (3, 'H001', 3.0, 4.5, 0.5, 2.0, 98);
-- Error: depth_from 4.0 overlaps with previous depth_to 4.5 (Correction should make it 4.5 to 6.0)
INSERT INTO core_assays VALUES (4, 'H001', 4.0, 6.0, 0.6, 2.5, 92); 

-- H002: Testing Significant Intercept (MATCH_RECOGNIZE)
INSERT INTO collars VALUES ('H002', 500100, 6000100, 410, 100, SYSDATE);
INSERT INTO core_assays VALUES (5, 'H002', 0, 10, 0.05, 0.5, 100);
-- Valid continuous sequence >= 3.0m where all au_gpt >= 0.5
INSERT INTO core_assays VALUES (6, 'H002', 10, 11.5, 1.2, 5.0, 98);
INSERT INTO core_assays VALUES (7, 'H002', 11.5, 13.0, 0.8, 3.5, 99);
INSERT INTO core_assays VALUES (8, 'H002', 13.0, 14.5, 2.1, 8.0, 97);
-- End sequence (length = 4.5m)
INSERT INTO core_assays VALUES (9, 'H002', 14.5, 20.0, 0.1, 1.0, 100);
-- Invalid sequence (all au_gpt >= 0.5 but length = 2.5m, which is < 3.0m)
INSERT INTO core_assays VALUES (10, 'H002', 20.0, 21.0, 1.5, 4.0, 90);
INSERT INTO core_assays VALUES (11, 'H002', 21.0, 22.5, 0.6, 2.0, 95);

-- H003: No significant intercepts, no overlaps
INSERT INTO collars VALUES ('H003', 500200, 6000200, 420, 100, SYSDATE);
INSERT INTO core_assays VALUES (12, 'H003', 0, 5, 0.01, 0.1, 100);
INSERT INTO core_assays VALUES (13, 'H003', 5, 6, 0.6, 1.0, 95);
-- Breaks sequence
INSERT INTO core_assays VALUES (14, 'H003', 6, 7.5, 0.4, 0.5, 98); 
INSERT INTO core_assays VALUES (15, 'H003', 7.5, 10, 1.8, 4.5, 99);

COMMIT;
EXIT;
EOSQL

echo "Data populated successfully."

# 5. Prepare export directory
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# 6. Pre-configure SQL Developer connection
ensure_hr_connection "GEO Database" "geo_admin" "Geo2024"
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="