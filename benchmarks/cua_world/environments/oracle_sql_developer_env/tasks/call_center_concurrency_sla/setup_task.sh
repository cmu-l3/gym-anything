#!/bin/bash
# Setup script for Call Center Concurrency & SLA Optimization task
echo "=== Setting up Call Center Concurrency Task ==="

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
echo "Cleaning up previous runs..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER wfm_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# 3. Create WFM_ANALYST schema
echo "Creating WFM_ANALYST user..."
oracle_query "CREATE USER wfm_analyst IDENTIFIED BY Wfm2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO wfm_analyst;
GRANT RESOURCE TO wfm_analyst;
GRANT CREATE VIEW TO wfm_analyst;
GRANT CREATE PROCEDURE TO wfm_analyst;
GRANT CREATE SESSION TO wfm_analyst;
GRANT CREATE TABLE TO wfm_analyst;
EXIT;" "system"

# 4. Create schema tables and generate Erlang C / Poisson simulation data
echo "Creating tables and generating Erlang-C simulated PBX data..."

sudo docker exec -i oracle-xe sqlplus -s wfm_analyst/Wfm2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE agents (
    agent_id NUMBER PRIMARY KEY,
    agent_name VARCHAR2(100),
    hire_date DATE,
    skill_group VARCHAR2(50)
);

CREATE TABLE call_logs (
    call_id NUMBER PRIMARY KEY,
    caller_phone VARCHAR2(20),
    start_time DATE,
    answered_time DATE,
    end_time DATE,
    agent_id NUMBER REFERENCES agents(agent_id),
    queue_name VARCHAR2(50),
    call_status VARCHAR2(20)
);

-- Generate realistic PBX data (15 days, ~15k calls) using statistical models
DECLARE
  v_start DATE := TRUNC(SYSDATE) - 15;
  v_curr DATE := v_start;
  v_phone VARCHAR2(20);
  v_wait_sec NUMBER;
  v_dur_sec NUMBER;
  v_status VARCHAR2(20);
  v_queue VARCHAR2(50);
  v_answered DATE;
  v_end DATE;
  v_agent NUMBER;
BEGIN
  -- Insert some agents
  FOR i IN 1..50 LOOP
    INSERT INTO agents VALUES (i, 'Agent ' || i, SYSDATE - 365, 'TIER1');
  END LOOP;

  DBMS_RANDOM.SEED(12345);
  
  FOR i IN 1..15000 LOOP
    -- Poisson arrivals (exponential inter-arrival time)
    -- Average 1000 calls/day -> ~86 seconds between calls
    v_curr := v_curr + (-LN(DBMS_RANDOM.VALUE(0.0001, 1)) * 86) / 86400;

    v_queue := CASE TRUNC(DBMS_RANDOM.VALUE(1,4)) WHEN 1 THEN 'SUPPORT' WHEN 2 THEN 'SALES' ELSE 'BILLING' END;
    v_agent := TRUNC(DBMS_RANDOM.VALUE(1, 51));

    -- Simulate repeat callers (5% chance)
    IF DBMS_RANDOM.VALUE < 0.05 THEN
       v_phone := '555-01' || LPAD(TRUNC(DBMS_RANDOM.VALUE(10, 99)), 2, '0');
    ELSE
       v_phone := '555-' || LPAD(TRUNC(DBMS_RANDOM.VALUE(100, 999)), 3, '0') || '-' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1000, 9999)), 4, '0');
    END IF;

    -- Erlang C wait time simulation (Peak vs Non-Peak)
    IF TO_CHAR(v_curr, 'HH24') IN ('09','10','14','15') THEN
       v_wait_sec := DBMS_RANDOM.NORMAL * 100 + 120; -- higher waits
    ELSE
       v_wait_sec := DBMS_RANDOM.NORMAL * 30 + 40;
    END IF;
    IF v_wait_sec < 2 THEN v_wait_sec := DBMS_RANDOM.VALUE(2, 10); END IF;

    v_dur_sec := DBMS_RANDOM.NORMAL * 180 + 300;
    IF v_dur_sec < 30 THEN v_dur_sec := 30; END IF;

    -- Abandonment behavior
    IF v_wait_sec > 90 AND DBMS_RANDOM.VALUE < 0.4 THEN
       v_status := 'ABANDONED';
       v_answered := NULL;
       v_agent := NULL;
       v_end := v_curr + (v_wait_sec / 86400);
    ELSE
       v_status := 'ANSWERED';
       v_answered := v_curr + (v_wait_sec / 86400);
       v_end := v_answered + (v_dur_sec / 86400);
    END IF;

    INSERT INTO call_logs (call_id, caller_phone, start_time, answered_time, end_time, agent_id, queue_name, call_status)
    VALUES (i, v_phone, v_curr, v_answered, v_end, v_agent, v_queue, v_status);
  END LOOP;
  COMMIT;
END;
/
EXIT;
EOSQL

echo "Data generation complete."

# 5. Pre-configure SQL Developer Connection
echo "Pre-configuring SQL Developer connection..."
ensure_hr_connection "WFM Database" "wfm_analyst" "Wfm2024"

# 6. Prepare Export Directory
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# 7. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="