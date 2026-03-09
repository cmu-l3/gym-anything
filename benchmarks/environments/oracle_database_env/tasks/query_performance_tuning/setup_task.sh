#!/bin/bash
# Setup for query_performance_tuning task
# Downloads real OpenFlights data, loads into Oracle, plants slow_queries.sql

set -e

echo "=== Setting up Query Performance Tuning Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/7] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Clean up prior artifacts ---
echo "[2/7] Cleaning prior task artifacts..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE flight_routes CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE airports CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/slow_queries.sql
rm -f /home/ga/Desktop/optimized_queries.sql
rm -f /tmp/openflights_airports.dat
rm -f /tmp/openflights_routes.dat

# --- Download OpenFlights data ---
echo "[3/7] Downloading OpenFlights airport and route data..."
curl -fsSL "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat" \
    -o /tmp/openflights_airports.dat 2>/dev/null || \
wget -q "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat" \
    -O /tmp/openflights_airports.dat

curl -fsSL "https://raw.githubusercontent.com/jpatokal/openflights/master/data/routes.dat" \
    -o /tmp/openflights_routes.dat 2>/dev/null || \
wget -q "https://raw.githubusercontent.com/jpatokal/openflights/master/data/routes.dat" \
    -O /tmp/openflights_routes.dat

AIRPORT_LINES=$(wc -l < /tmp/openflights_airports.dat)
ROUTE_LINES=$(wc -l < /tmp/openflights_routes.dat)
echo "  Downloaded: $AIRPORT_LINES airport records, $ROUTE_LINES route records"

if [ "$AIRPORT_LINES" -lt 10000 ]; then
    echo "ERROR: Airport data download incomplete ($AIRPORT_LINES lines)"
    exit 1
fi

# --- Create tables ---
echo "[4/7] Creating AIRPORTS and FLIGHT_ROUTES tables..."
oracle_query "
CREATE TABLE airports (
    airport_id   NUMBER(6)     PRIMARY KEY,
    name         VARCHAR2(200),
    city         VARCHAR2(100),
    country      VARCHAR2(100),
    iata_code    VARCHAR2(3),
    icao_code    VARCHAR2(4),
    latitude     NUMBER(10,6),
    longitude    NUMBER(10,6),
    altitude_ft  NUMBER(6),
    timezone_offset NUMBER(4,1),
    dst_type     VARCHAR2(1),
    tz_name      VARCHAR2(60),
    airport_type VARCHAR2(20),
    data_source  VARCHAR2(20)
);
CREATE TABLE flight_routes (
    route_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    airline_code   VARCHAR2(3),
    airline_id     NUMBER,
    src_iata       VARCHAR2(4),
    src_airport_id NUMBER,
    dst_iata       VARCHAR2(4),
    dst_airport_id NUMBER,
    codeshare      VARCHAR2(1),
    stops          NUMBER(2),
    equipment      VARCHAR2(50)
);
" "hr" > /dev/null 2>&1

# --- Load airports via Python ---
echo "[5/7] Loading airport and route data into Oracle..."
python3 << 'PYEOF'
import csv
import oracledb
import sys

conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
cursor = conn.cursor()

# Load airports
airport_rows = []
with open("/tmp/openflights_airports.dat", "r", encoding="utf-8", errors="replace") as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) < 14:
            continue
        try:
            airport_id = int(row[0]) if row[0].strip() and row[0].strip() != "\\N" else None
            if airport_id is None:
                continue
            def clean(v, maxlen=None):
                v = v.strip().strip('"')
                if v == "\\N" or v == "":
                    return None
                return v[:maxlen] if maxlen else v
            def clean_num(v):
                v = v.strip().strip('"')
                if v == "\\N" or v == "":
                    return None
                try:
                    return float(v)
                except:
                    return None
            airport_rows.append((
                airport_id,
                clean(row[1], 200),
                clean(row[2], 100),
                clean(row[3], 100),
                clean(row[4], 3),
                clean(row[5], 4),
                clean_num(row[6]),
                clean_num(row[7]),
                clean_num(row[8]),
                clean_num(row[9]),
                clean(row[10], 1),
                clean(row[11], 60),
                clean(row[12], 20),
                clean(row[13], 20),
            ))
        except Exception:
            continue

cursor.executemany("""
    INSERT INTO airports (airport_id, name, city, country, iata_code, icao_code,
        latitude, longitude, altitude_ft, timezone_offset, dst_type, tz_name,
        airport_type, data_source)
    VALUES (:1,:2,:3,:4,:5,:6,:7,:8,:9,:10,:11,:12,:13,:14)
""", airport_rows)
conn.commit()
print(f"Loaded {len(airport_rows)} airports")

# Load routes
route_rows = []
with open("/tmp/openflights_routes.dat", "r", encoding="utf-8", errors="replace") as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) < 9:
            continue
        try:
            def rclean(v, maxlen=None):
                v = v.strip().strip('"')
                if v == "\\N" or v == "":
                    return None
                return v[:maxlen] if maxlen else v
            def rnum(v):
                v = v.strip().strip('"')
                if v == "\\N" or v == "":
                    return None
                try:
                    return int(v)
                except:
                    return None
            route_rows.append((
                rclean(row[0], 3),
                rnum(row[1]),
                rclean(row[2], 4),
                rnum(row[3]),
                rclean(row[4], 4),
                rnum(row[5]),
                rclean(row[6], 1),
                rnum(row[7]),
                rclean(row[8], 50),
            ))
        except Exception:
            continue

# Insert in batches of 5000
batch_size = 5000
for i in range(0, len(route_rows), batch_size):
    batch = route_rows[i:i+batch_size]
    cursor.executemany("""
        INSERT INTO flight_routes (airline_code, airline_id, src_iata, src_airport_id,
            dst_iata, dst_airport_id, codeshare, stops, equipment)
        VALUES (:1,:2,:3,:4,:5,:6,:7,:8,:9)
    """, batch)
    conn.commit()

print(f"Loaded {len(route_rows)} routes")
cursor.close()
conn.close()
PYEOF

# --- Verify data loaded ---
AIRPORT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM airports;" "hr" 2>/dev/null | tr -d ' ')
ROUTE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM flight_routes;" "hr" 2>/dev/null | tr -d ' ')
echo "  Verified: $AIRPORT_COUNT airports, $ROUTE_COUNT routes in Oracle"

if [ -z "$AIRPORT_COUNT" ] || [ "$AIRPORT_COUNT" -lt 10000 ]; then
    echo "ERROR: Insufficient airport data loaded"
    exit 1
fi

# --- Plant slow_queries.sql ---
echo "[6/7] Creating slow_queries.sql on Desktop..."
cat > /home/ga/Desktop/slow_queries.sql << 'SQLEOF'
-- Query 1: Find all airports in United States ordered by city
-- ISSUE: No index on country column — full table scan
SELECT airport_id, name, city, iata_code, altitude_ft
FROM airports
WHERE country = 'United States'
ORDER BY city;

-- Query 2: Find high-altitude airports in Canada and Russia above 5000 ft
-- ISSUE: No composite index on (country, altitude_ft) — full scan
SELECT airport_id, name, city, country, altitude_ft
FROM airports
WHERE country IN ('Canada', 'Russia')
  AND altitude_ft > 5000
ORDER BY altitude_ft DESC;

-- Query 3: Count routes per source airport (top 20 busiest hubs)
-- ISSUE: No index on src_iata in flight_routes — full scan on 67k rows
SELECT a.iata_code, a.name, a.city, a.country, COUNT(r.route_id) AS route_count
FROM airports a
JOIN flight_routes r ON a.iata_code = r.src_iata
GROUP BY a.iata_code, a.name, a.city, a.country
ORDER BY route_count DESC
FETCH FIRST 20 ROWS ONLY;

-- Query 4: Find all direct routes between two specific airports
-- ISSUE: No composite index on (src_iata, dst_iata) — full scan
SELECT r.airline_code, r.src_iata, r.dst_iata, r.stops, r.equipment
FROM flight_routes r
WHERE r.src_iata = 'JFK'
  AND r.dst_iata = 'LAX';

-- Query 5: Codeshare analysis — find airports with the most codeshare routes departing
-- ISSUE: No index on codeshare column — full scan with filter
SELECT a.iata_code, a.name, a.country, COUNT(*) AS codeshare_count
FROM flight_routes r
JOIN airports a ON r.src_airport_id = a.airport_id
WHERE r.codeshare = 'Y'
GROUP BY a.iata_code, a.name, a.country
ORDER BY codeshare_count DESC
FETCH FIRST 15 ROWS ONLY;
SQLEOF

chown ga:ga /home/ga/Desktop/slow_queries.sql

# --- Record baseline ---
echo "[7/7] Recording baseline state..."
date +%s > /tmp/task_start_timestamp
chmod 600 /tmp/task_start_timestamp

echo "${AIRPORT_COUNT}" > /tmp/initial_airport_count_perf
echo "${ROUTE_COUNT}" > /tmp/initial_route_count_perf
chmod 600 /tmp/initial_airport_count_perf /tmp/initial_route_count_perf

# Count existing indexes on our tables before task
INDEX_COUNT=$(oracle_query_raw "
SELECT COUNT(*) FROM user_indexes
WHERE table_name IN ('AIRPORTS','FLIGHT_ROUTES')
  AND index_type != 'LOB';" "hr" 2>/dev/null | tr -d ' ')
echo "${INDEX_COUNT:-0}" > /tmp/initial_index_count_perf
chmod 600 /tmp/initial_index_count_perf

# --- Ensure DBeaver is running ---
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "dbeaver"; then
    su - ga -c "DISPLAY=:1 /snap/bin/dbeaver-ce &" > /dev/null 2>&1 || true
    sleep 6
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Query Performance Tuning Setup Complete ==="
echo "  Airports loaded: $AIRPORT_COUNT"
echo "  Routes loaded: $ROUTE_COUNT"
echo "  Initial indexes (system-created): $INDEX_COUNT"
echo "  Slow queries file: /home/ga/Desktop/slow_queries.sql"
