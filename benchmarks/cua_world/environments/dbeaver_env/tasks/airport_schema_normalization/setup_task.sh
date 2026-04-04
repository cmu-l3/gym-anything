#!/bin/bash
# Setup script for airport_schema_normalization task
# Downloads OpenFlights airport data and creates flat SQLite table

set -e
echo "=== Setting up Airport Schema Normalization Task ==="

source /workspace/scripts/task_utils.sh

AIRPORTS_DB="/home/ga/Documents/databases/airports_flat.db"
DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"

mkdir -p "$DB_DIR" "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/

# Remove any pre-existing outputs
rm -f "$EXPORT_DIR/normalization_report.txt"

# Remove old airports database to ensure fresh state
rm -f "$AIRPORTS_DB"

# Download and create the airports flat database
echo "Downloading OpenFlights airport data..."
DOWNLOAD_SUCCESS=false

# Primary source: OpenFlights GitHub
if wget -q --timeout=60 \
    "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat" \
    -O /tmp/airports.dat 2>/dev/null && [ -s /tmp/airports.dat ]; then
    echo "Downloaded airports.dat ($(wc -l < /tmp/airports.dat) lines)"
    DOWNLOAD_SUCCESS=true
fi

# Fallback source
if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
    echo "Trying fallback source..."
    if wget -q --timeout=60 \
        "https://raw.githubusercontent.com/jpatokal/openflights/refs/heads/master/data/airports.dat" \
        -O /tmp/airports.dat 2>/dev/null && [ -s /tmp/airports.dat ]; then
        DOWNLOAD_SUCCESS=true
    fi
fi

if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
    echo "ERROR: Could not download airports data"
    exit 1
fi

echo "Creating airports_flat.db SQLite database..."
python3 << 'PYEOF'
import csv
import sqlite3
import json
import sys

db_path = "/home/ga/Documents/databases/airports_flat.db"
dat_path = "/tmp/airports.dat"

conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create the flat table (denormalized)
c.execute("DROP TABLE IF EXISTS airports_raw")
c.execute("""
CREATE TABLE airports_raw (
    airport_id INTEGER,
    name TEXT,
    city TEXT,
    country TEXT,
    iata_code TEXT,
    icao_code TEXT,
    latitude REAL,
    longitude REAL,
    altitude INTEGER,
    timezone_offset REAL,
    dst_type TEXT,
    tz_name TEXT,
    type TEXT,
    source TEXT
)
""")

# Parse the airports.dat file (CSV, no header)
# Format: ID, Name, City, Country, IATA, ICAO, Lat, Lon, Alt, TZ, DST, TzDB, Type, Source
inserted = 0
skipped = 0

with open(dat_path, 'r', encoding='utf-8', errors='replace') as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) < 12:
            skipped += 1
            continue
        try:
            airport_id = int(row[0]) if row[0] and row[0] != r'\N' else None
            name = row[1] if row[1] != r'\N' else None
            city = row[2] if row[2] != r'\N' else None
            country = row[3] if row[3] != r'\N' else None
            iata = row[4] if row[4] not in (r'\N', '') else None
            icao = row[5] if row[5] not in (r'\N', '') else None
            lat = float(row[6]) if row[6] not in (r'\N', '') else None
            lon = float(row[7]) if row[7] not in (r'\N', '') else None
            alt = int(row[8]) if row[8] not in (r'\N', '') else None
            tz_offset = float(row[9]) if row[9] not in (r'\N', '') else None
            dst = row[10] if row[10] not in (r'\N', '') else None
            tz_name = row[11] if row[11] not in (r'\N', '') else None
            ap_type = row[12] if len(row) > 12 and row[12] not in (r'\N', '') else None
            ap_source = row[13] if len(row) > 13 and row[13] not in (r'\N', '') else None

            c.execute("""INSERT INTO airports_raw VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                      (airport_id, name, city, country, iata, icao,
                       lat, lon, alt, tz_offset, dst, tz_name, ap_type, ap_source))
            inserted += 1
        except Exception as e:
            skipped += 1

conn.commit()

# Compute ground truth counts
total_count = c.execute("SELECT COUNT(*) FROM airports_raw").fetchone()[0]
country_count = c.execute("SELECT COUNT(DISTINCT country) FROM airports_raw WHERE country IS NOT NULL").fetchone()[0]
tz_count = c.execute("SELECT COUNT(DISTINCT tz_name) FROM airports_raw WHERE tz_name IS NOT NULL").fetchone()[0]

print(f"Inserted: {inserted}, Skipped: {skipped}, Total: {total_count}")
print(f"Countries: {country_count}, Timezones: {tz_count}")

# Save ground truth
ground_truth = {
    "original_count": total_count,
    "country_count": country_count,
    "timezone_count": tz_count,
    "inserted": inserted
}

with open('/tmp/airports_normalization_gt.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved to /tmp/airports_normalization_gt.json")
conn.close()
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create airports database"
    exit 1
fi

chown ga:ga "$AIRPORTS_DB"

# Verify the database
AIRPORT_COUNT=$(sqlite3 "$AIRPORTS_DB" "SELECT COUNT(*) FROM airports_raw" 2>/dev/null || echo 0)
echo "Airports in database: $AIRPORT_COUNT"

if [ "$AIRPORT_COUNT" -lt 5000 ]; then
    echo "ERROR: Airport database has too few records ($AIRPORT_COUNT)"
    exit 1
fi

# Record baseline state
echo "$AIRPORT_COUNT" > /tmp/initial_airports_raw_count

# Check that no normalized tables exist yet (clean state)
INITIAL_TABLES=$(sqlite3 "$AIRPORTS_DB" "SELECT name FROM sqlite_master WHERE type='table'" 2>/dev/null)
echo "Initial tables: $INITIAL_TABLES"
echo "$INITIAL_TABLES" > /tmp/initial_airport_tables

# Record DBeaver connections baseline
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
INITIAL_CONN_COUNT=0
if [ -f "$DBEAVER_CONFIG" ]; then
    INITIAL_CONN_COUNT=$(python3 -c "
import json
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    print(len(config.get('connections', {})))
except:
    print(0)
" 2>/dev/null || echo 0)
fi
echo "$INITIAL_CONN_COUNT" > /tmp/initial_dbeaver_conn_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(date)"

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" 2>/dev/null &
    sleep 8
fi
focus_dbeaver || true
sleep 2

# Cleanup download
rm -f /tmp/airports.dat

take_screenshot /tmp/airports_task_start.png
echo "=== Airport Schema Normalization Setup Complete ==="
