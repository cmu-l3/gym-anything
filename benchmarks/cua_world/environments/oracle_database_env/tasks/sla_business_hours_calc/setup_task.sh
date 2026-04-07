#!/bin/bash
# Setup script for SLA Business Hours Calculation Task
# Creates SUPPORT_TICKETS and PUBLIC_HOLIDAYS tables with specific edge-case data.

set -e

echo "=== Setting up SLA Business Hours Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Verify HR schema connectivity ---
echo "[2/4] Verifying HR schema connectivity..."
for attempt in 1 2 3; do
    if oracle_query_raw "SELECT 1 FROM dual;" "hr" > /dev/null 2>&1; then
        echo "  HR schema ready."
        break
    fi
    echo "  Attempt $attempt failed, waiting 10s..."
    sleep 10
    if [ $attempt -eq 3 ]; then
        echo "ERROR: Cannot connect to HR schema"
        exit 1
    fi
done

# --- Clean up prior artifacts ---
echo "[3/4] Cleaning up old tables/views..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW sla_performance_vw';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE support_tickets CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE public_holidays CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/sla_report.csv

# --- Create and Populate Tables ---
echo "[4/4] Creating tables and planting trap data..."

# We use specific dates to control weekends.
# Jan 1, 2024 is a Monday.
# Jan 5, 2024 is Friday. Jan 6=Sat, Jan 7=Sun, Jan 8=Mon.

oracle_query "
CREATE TABLE public_holidays (
    holiday_date DATE PRIMARY KEY,
    description  VARCHAR2(100)
);

CREATE TABLE support_tickets (
    ticket_id   NUMBER PRIMARY KEY,
    opened_at   DATE,
    closed_at   DATE,
    priority    VARCHAR2(20),
    description VARCHAR2(200)
);

-- HOLIDAY: Monday Jan 8, 2024
INSERT INTO public_holidays VALUES (TO_DATE('2024-01-08', 'YYYY-MM-DD'), 'Company Founder Day');
INSERT INTO public_holidays VALUES (TO_DATE('2024-12-25', 'YYYY-MM-DD'), 'Christmas');

-- TRAP 1: Weekend Spanner (ID 1001)
-- Fri Jan 5 16:00 -> Mon Jan 8 (Holiday) -> Tue Jan 9 10:00?
-- Let's make it simpler first: Fri Jan 12 16:00 -> Mon Jan 15 10:00 (No holiday)
-- Fri 16-17 (60m) + Sat(0) + Sun(0) + Mon 09-10 (60m) = 120 mins
INSERT INTO support_tickets VALUES (1001, 
    TO_DATE('2024-01-12 16:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    TO_DATE('2024-01-15 10:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    'HIGH', 'Weekend Spanner');

-- TRAP 2: Holiday Hit (ID 1002)
-- Fri Jan 5 16:30 -> Tue Jan 9 09:30 (Mon Jan 8 is Holiday)
-- Fri 16:30-17:00 (30m) + Sat(0) + Sun(0) + Mon(0 Holiday) + Tue 09:00-09:30 (30m) = 60 mins
INSERT INTO support_tickets VALUES (1002, 
    TO_DATE('2024-01-05 16:30:00', 'YYYY-MM-DD HH24:MI:SS'),
    TO_DATE('2024-01-09 09:30:00', 'YYYY-MM-DD HH24:MI:SS'),
    'CRITICAL', 'Holiday Hit');

-- TRAP 3: Late Start (ID 1003)
-- Tue Jan 16 20:00 (After hours) -> Wed Jan 17 09:15
-- Tue (0) -> Wed starts 09:00 -> 09:15 = 15 mins
INSERT INTO support_tickets VALUES (1003, 
    TO_DATE('2024-01-16 20:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    TO_DATE('2024-01-17 09:15:00', 'YYYY-MM-DD HH24:MI:SS'),
    'LOW', 'Late Start');

-- TRAP 4: Same Day (ID 1004)
-- Wed Jan 17 10:00 -> Wed Jan 17 11:30
-- 90 mins
INSERT INTO support_tickets VALUES (1004, 
    TO_DATE('2024-01-17 10:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    TO_DATE('2024-01-17 11:30:00', 'YYYY-MM-DD HH24:MI:SS'),
    'MEDIUM', 'Same Day Standard');

-- Fillers
INSERT INTO support_tickets VALUES (1005, TO_DATE('2024-01-18 09:00:00', 'YYYY-MM-DD HH24:MI:SS'), TO_DATE('2024-01-18 17:00:00', 'YYYY-MM-DD HH24:MI:SS'), 'MEDIUM', 'Full Day');

COMMIT;
" "hr"

# Record start time
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Tables created: SUPPORT_TICKETS, PUBLIC_HOLIDAYS"
echo "Data loaded with edge cases."