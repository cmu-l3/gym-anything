#!/bin/bash
echo "=== Setting up Actuarial Loss Reserve Triangulation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# Clean up previous run artifacts
echo "Setting up ACTUARY_ADMIN schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER actuary_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER actuary_admin IDENTIFIED BY Reserve2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE TO actuary_admin;
GRANT CREATE VIEW TO actuary_admin;
GRANT CREATE SESSION TO actuary_admin;
GRANT CREATE TABLE TO actuary_admin;
EXIT;" "system"

echo "ACTUARY_ADMIN user created."

echo "Creating SCHEDULE_P_RAW table and generating synthetic actuarial data..."
sudo docker exec -i oracle-xe sqlplus -s actuary_admin/Reserve2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE schedule_p_raw (
    group_code VARCHAR2(10),
    company_name VARCHAR2(100),
    line_of_business VARCHAR2(50),
    accident_year NUMBER(4),
    development_lag NUMBER(2),
    cumulative_paid_loss NUMBER(15,2)
);

BEGIN
  -- Company 1767: Commercial Auto (Target company for triangle)
  FOR ay IN 2014..2023 LOOP
    FOR dlag IN 1..(2024 - ay) LOOP
      IF dlag <= 10 THEN
        INSERT INTO schedule_p_raw VALUES ('1767', 'Target Re', 'Commercial Auto', ay, dlag, ROUND(1000 * ay * (1 - 1/(dlag+1)), 2));
      END IF;
    END LOOP;
  END LOOP;
  
  -- Company 2000: Commercial Auto (Peer)
  FOR ay IN 2014..2023 LOOP
    FOR dlag IN 1..(2024 - ay) LOOP
      IF dlag <= 10 THEN
        INSERT INTO schedule_p_raw VALUES ('2000', 'Peer A', 'Commercial Auto', ay, dlag, ROUND(2000 * ay * (1 - 1/(dlag+2)), 2));
      END IF;
    END LOOP;
  END LOOP;
  
  -- Company 3000: Commercial Auto (Missing lag 3 for AY 2021 to test volume weighting exclusion)
  FOR ay IN 2014..2023 LOOP
    FOR dlag IN 1..(2024 - ay) LOOP
      IF dlag <= 10 THEN
        IF NOT (ay = 2021 AND dlag = 3) THEN
          INSERT INTO schedule_p_raw VALUES ('3000', 'Peer B', 'Commercial Auto', ay, dlag, ROUND(1500 * ay * (1 - 1/(dlag+1.5)), 2));
        END IF;
      END IF;
    END LOOP;
  END LOOP;
  
  -- Company 1767: Workers Comp (Different Line of Business to test filtering logic)
  FOR ay IN 2014..2023 LOOP
    FOR dlag IN 1..(2024 - ay) LOOP
      IF dlag <= 10 THEN
        INSERT INTO schedule_p_raw VALUES ('1767', 'Target Re', 'Workers Comp', ay, dlag, ROUND(500 * ay * (1 - 1/(dlag+1.2)), 2));
      END IF;
    END LOOP;
  END LOOP;
  
  COMMIT;
END;
/
EXIT;
EOSQL

echo "Data populated successfully."

# Pre-configure and open connection in SQL Developer
ensure_hr_connection "Actuary Database" "actuary_admin" "Reserve2024"
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="