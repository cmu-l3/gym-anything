#!/bin/bash
# Setup for logistics_journey_segmentation task
# Creates the CONTAINER_LOGS table and populates it with "Gaps and Islands" test data

set -e

echo "=== Setting up Logistics Journey Segmentation Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Clean up prior artifacts ---
echo "[2/4] Cleaning up prior artifacts..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW journey_segments';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE container_logs PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/journey_report.csv

# --- Create Table ---
echo "[3/4] Creating CONTAINER_LOGS table..."
oracle_query "
CREATE TABLE container_logs (
    log_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    container_id NUMBER NOT NULL,
    status VARCHAR2(20) NOT NULL,
    log_time TIMESTAMP NOT NULL
);
" "hr" > /dev/null 2>&1

# --- Populate Data using PL/SQL ---
# We use PL/SQL to generate the sequences to ensure precise control over the "Islands"
echo "[4/4] Populating test data..."
oracle_query "
DECLARE
    -- Helper to insert a range of logs
    PROCEDURE insert_segment(
        p_cid IN NUMBER, 
        p_status IN VARCHAR2, 
        p_start_time IN TIMESTAMP, 
        p_count IN NUMBER
    ) IS
    BEGIN
        FOR i IN 0..p_count-1 LOOP
            INSERT INTO container_logs (container_id, status, log_time)
            VALUES (p_cid, p_status, p_start_time + NUMTODSINTERVAL(i * 15, 'MINUTE'));
        END LOOP;
    END;
BEGIN
    -- CONTAINER 101: Standard Journey (4 Segments)
    -- 1. TRANSIT (8 pings, 2 hours)
    insert_segment(101, 'IN_TRANSIT', TIMESTAMP '2024-03-01 10:00:00', 8);
    -- 2. CUSTOMS (4 pings, 1 hour)
    insert_segment(101, 'CUSTOMS',    TIMESTAMP '2024-03-01 12:00:00', 4);
    -- 3. TRANSIT (4 pings, 1 hour) - RECURRING STATUS (The Island Test)
    insert_segment(101, 'IN_TRANSIT', TIMESTAMP '2024-03-01 13:00:00', 4);
    -- 4. DOCKED (4 pings, 1 hour)
    insert_segment(101, 'DOCKED',     TIMESTAMP '2024-03-01 14:00:00', 4);

    -- CONTAINER 102: Sitting Still (1 Segment)
    -- 1. DOCKED (20 pings, 5 hours)
    insert_segment(102, 'DOCKED',     TIMESTAMP '2024-03-02 08:00:00', 20);

    -- CONTAINER 103: Erratic (5 Segments)
    -- A-B-A-B-C pattern
    insert_segment(103, 'IN_TRANSIT', TIMESTAMP '2024-03-03 09:00:00', 2);
    insert_segment(103, 'ERROR',      TIMESTAMP '2024-03-03 09:30:00', 2);
    insert_segment(103, 'IN_TRANSIT', TIMESTAMP '2024-03-03 10:00:00', 2);
    insert_segment(103, 'ERROR',      TIMESTAMP '2024-03-03 10:30:00', 2);
    insert_segment(103, 'DOCKED',     TIMESTAMP '2024-03-03 11:00:00', 2);

    COMMIT;
END;
/
" "hr" > /dev/null 2>&1

# Verify load
ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM container_logs;" "hr" | tr -d ' ')
echo "Loaded $ROW_COUNT log entries."

# Record start time
date +%s > /tmp/task_start_timestamp

# Ensure DBeaver is ready
if ! pgrep -f dbeaver > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /snap/bin/dbeaver-ce &" > /dev/null 2>&1 || true
fi

echo "=== Setup Complete ==="