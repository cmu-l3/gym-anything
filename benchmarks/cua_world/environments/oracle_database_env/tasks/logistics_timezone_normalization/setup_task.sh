#!/bin/bash
# Setup script for logistics_timezone_normalization
# Creates schema with 'wall-clock' flight data specifically designed to break naive date math

set -e

echo "=== Setting up Logistics Timezone Task ==="

source /workspace/scripts/task_utils.sh

# --- 1. Verify Oracle Container ---
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- 2. Clean up previous artifacts ---
oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP VIEW v_flight_analysis';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE flight_logs CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE airport_ref CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
" "hr" > /dev/null 2>&1

rm -f /home/ga/Desktop/long_haul_report.csv

# --- 3. Create Tables ---
# AIRPORT_REF: Maps IATA codes to IANA Timezone Regions
# FLIGHT_LOGS: specific flights with local times
echo "Creating tables..."
oracle_query "
CREATE TABLE airport_ref (
    iata_code VARCHAR2(3) PRIMARY KEY,
    city VARCHAR2(50),
    iana_timezone VARCHAR2(50)
);

CREATE TABLE flight_logs (
    flight_id NUMBER PRIMARY KEY,
    airline VARCHAR2(3),
    src_iata VARCHAR2(3),
    dst_iata VARCHAR2(3),
    depart_time_local DATE,
    arrive_time_local DATE,
    CONSTRAINT fk_src FOREIGN KEY (src_iata) REFERENCES airport_ref(iata_code),
    CONSTRAINT fk_dst FOREIGN KEY (dst_iata) REFERENCES airport_ref(iata_code)
);
" "hr"

# --- 4. Insert Data (Crucial for Verification) ---

# Reference Data
oracle_query "
INSERT INTO airport_ref VALUES ('JFK', 'New York', 'America/New_York');
INSERT INTO airport_ref VALUES ('LHR', 'London', 'Europe/London');
INSERT INTO airport_ref VALUES ('LAX', 'Los Angeles', 'America/Los_Angeles');
INSERT INTO airport_ref VALUES ('HND', 'Tokyo', 'Asia/Tokyo');
INSERT INTO airport_ref VALUES ('SFO', 'San Francisco', 'America/San_Francisco');
INSERT INTO airport_ref VALUES ('SYD', 'Sydney', 'Australia/Sydney');
INSERT INTO airport_ref VALUES ('DXB', 'Dubai', 'Asia/Dubai');
COMMIT;
" "hr"

# Flight Data - Designed to test edge cases
# Flight 100: HND -> SFO (Date Line Crossing)
#   Departs: Jan 1 18:00 Tokyo
#   Arrives: Jan 1 10:30 SF (Same day, earlier time locally)
#   Naive math: 10:30 - 18:00 = negative duration
#   Real Math: Tokyo is UTC+9, SF is UTC-8. 17h diff. Flight ~9.5h.

# Flight 200: LAX -> JFK (Standard Domestic)
#   Departs: Mar 10 08:00 LA
#   Arrives: Mar 10 16:30 NY

# Flight 800: SYD -> LAX (Long Haul > 800 mins, for CSV report)
#   Departs: Feb 15 10:00 Sydney
#   Arrives: Feb 15 06:00 LAX (Arrives 'before' it left)
#   Duration: ~14h (840 mins)

# Flight 900: GAP WEEK TEST (The "Anti-Gaming" trap)
#   Date: March 15, 2024.
#   USA started DST on Mar 10. UK starts DST on Mar 31.
#   Gap: NY is UTC-4. London is UTC+0. Difference is 4 hours (usually 5).
#   Departs: JFK 18:00 (Local) -> Arrives LHR 06:00 (Local next day)
#   UTC Dep: 22:00. UTC Arr: 06:00.
#   Duration: 8 hours (480 mins).
#   If agent uses hardcoded -5 offset: Dep 23:00 UTC. Duration 7 hours. -> FAIL.

echo "Inserting flight data..."
oracle_query "
INSERT INTO flight_logs VALUES (100, 'JAL', 'HND', 'SFO', 
    TO_DATE('2024-01-01 18:00:00', 'YYYY-MM-DD HH24:MI:SS'), 
    TO_DATE('2024-01-01 10:30:00', 'YYYY-MM-DD HH24:MI:SS'));

INSERT INTO flight_logs VALUES (200, 'DAL', 'LAX', 'JFK', 
    TO_DATE('2024-03-10 08:00:00', 'YYYY-MM-DD HH24:MI:SS'), 
    TO_DATE('2024-03-10 16:30:00', 'YYYY-MM-DD HH24:MI:SS'));

INSERT INTO flight_logs VALUES (800, 'QFA', 'SYD', 'LAX', 
    TO_DATE('2024-02-15 10:00:00', 'YYYY-MM-DD HH24:MI:SS'), 
    TO_DATE('2024-02-15 06:00:00', 'YYYY-MM-DD HH24:MI:SS'));

INSERT INTO flight_logs VALUES (900, 'BAW', 'JFK', 'LHR', 
    TO_DATE('2024-03-15 18:00:00', 'YYYY-MM-DD HH24:MI:SS'), 
    TO_DATE('2024-03-16 06:00:00', 'YYYY-MM-DD HH24:MI:SS'));

COMMIT;
" "hr"

# --- 5. Initial State Recording ---
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

# Ensure DBeaver is ready (installed in env, but ensure no blocking processes)
pkill -f dbeaver 2>/dev/null || true

echo "=== Setup Complete ==="