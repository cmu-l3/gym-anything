#!/bin/bash
set -euo pipefail

echo "=== Setup: aggregate_hotel_country_metrics ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh
wait_for_orientdb 90

rm -f /tmp/aggregate_hotel_country_metrics_result.json \
      /tmp/aggregate_hotel_country_metrics_baseline.json \
      /tmp/task_start_timestamp 2>/dev/null || true

# Remove prior HotelCountryMetrics artifacts
orientdb_sql "demodb" "DELETE VERTEX HotelCountryMetrics" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX HotelCountryMetrics.Country" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS HotelCountryMetrics UNSAFE" >/dev/null 2>&1 || true

# Seed the 15 canonical hotels.
# Strategy: DROP Hotels.Id UNIQUE index (which blocks null-Id INSERTs after the first),
# then INSERT canonical hotels, then DELETE VERTEX the Italian null-Country records.
# The built-in OrientDB DemoDB Italian hotels have non-null OSM Id values in a Hotels.Id
# UNIQUE index. Canonical inserts don't specify Id (null), so INSERT #1 succeeds but
# INSERT #2 fails with UNIQUE constraint violation. Dropping the index first fixes this.
# DELETE VERTEX (not DELETE FROM) is required because Italian hotels have connected edges.
echo "Dropping Hotels.Id UNIQUE index to allow null-Id canonical inserts..."
orientdb_sql "demodb" "DROP INDEX Hotels.Id" >/dev/null 2>&1 || true

echo "Inserting 15 canonical hotels..."

# --- CRITICAL (Stars=5, Type in Luxury/Palace): 6 hotels ---
orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Hotel Adlon Kempinski', Type='Luxury', Phone='+49-30-2261-0', Latitude=52.5162, Longitude=13.3777, Street='Unter den Linden 77', City='Berlin', Country='Germany', Stars=5" >/dev/null \
  && echo "  Inserted: Hotel Adlon Kempinski" || echo "  WARNING: Hotel Adlon Kempinski failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Hotel de Crillon', Type='Palace', Phone='+33-1-44-71-15-00', Latitude=48.8679, Longitude=2.3215, Street='Place de la Concorde 10', City='Paris', Country='France', Stars=5" >/dev/null \
  && echo "  Inserted: Hotel de Crillon" || echo "  WARNING: Hotel de Crillon failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='The Savoy', Type='Luxury', Phone='+44-20-7836-4343', Latitude=51.5099, Longitude=-0.1201, Street='Strand', City='London', Country='United Kingdom', Stars=5" >/dev/null \
  && echo "  Inserted: The Savoy" || echo "  WARNING: The Savoy failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Park Hyatt Tokyo', Type='Luxury', Phone='+81-3-5322-1234', Latitude=35.6895, Longitude=139.6933, Street='Shinjuku 3-7-1-2', City='Tokyo', Country='Japan', Stars=5" >/dev/null \
  && echo "  Inserted: Park Hyatt Tokyo" || echo "  WARNING: Park Hyatt Tokyo failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Four Seasons Sydney', Type='Luxury', Phone='+61-2-9250-3100', Latitude=-33.8688, Longitude=151.2093, Street='George Street 199', City='Sydney', Country='Australia', Stars=5" >/dev/null \
  && echo "  Inserted: Four Seasons Sydney" || echo "  WARNING: Four Seasons Sydney failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Intercontinental Amsterdam', Type='Luxury', Phone='+31-20-655-6262', Latitude=52.3702, Longitude=4.9076, Street='Prof Tulpplein 1', City='Amsterdam', Country='Netherlands', Stars=5" >/dev/null \
  && echo "  Inserted: Intercontinental Amsterdam" || echo "  WARNING: Intercontinental Amsterdam failed"

# --- HIGH (Stars=5, Type NOT in Luxury/Palace): 6 hotels ---
orientdb_sql "demodb" "INSERT INTO Hotels SET Name='The Plaza Hotel', Type='Historic', Phone='+1-212-759-3000', Latitude=40.7645, Longitude=-73.9753, Street='Fifth Avenue', City='New York', Country='United States', Stars=5" >/dev/null \
  && echo "  Inserted: The Plaza Hotel" || echo "  WARNING: The Plaza Hotel failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Copacabana Palace', Type='Historic', Phone='+55-21-2548-7070', Latitude=-22.9697, Longitude=-43.1817, Street='Av Atlantica 1702', City='Rio de Janeiro', Country='Brazil', Stars=5" >/dev/null \
  && echo "  Inserted: Copacabana Palace" || echo "  WARNING: Copacabana Palace failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Hotel Arts Barcelona', Type='Boutique', Phone='+34-93-221-1000', Latitude=41.3851, Longitude=2.1967, Street='Marina 19-21', City='Barcelona', Country='Spain', Stars=5" >/dev/null \
  && echo "  Inserted: Hotel Arts Barcelona" || echo "  WARNING: Hotel Arts Barcelona failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Grande Bretagne Hotel', Type='Historic', Phone='+30-210-333-0000', Latitude=37.9754, Longitude=23.7367, Street='Syntagma Square 1', City='Athens', Country='Greece', Stars=5" >/dev/null \
  && echo "  Inserted: Grande Bretagne Hotel" || echo "  WARNING: Grande Bretagne Hotel failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Hotel Villa d Este', Type='Resort', Phone='+39-031-348-1', Latitude=45.8440, Longitude=9.0726, Street='Via Regina 40', City='Cernobbio', Country='Italy', Stars=5" >/dev/null \
  && echo "  Inserted: Hotel Villa d Este" || echo "  WARNING: Hotel Villa d Este failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Baglioni Hotel Luna', Type='Historic', Phone='+39-041-528-9840', Latitude=45.4341, Longitude=12.3401, Street='Riva degli Schiavoni 1243', City='Venice', Country='Italy', Stars=5" >/dev/null \
  && echo "  Inserted: Baglioni Hotel Luna" || echo "  WARNING: Baglioni Hotel Luna failed"

# --- STANDARD (Stars<5): 3 hotels ---
orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Hotel Artemide', Type='Boutique', Phone='+39-06-4884-6000', Latitude=41.8981, Longitude=12.4989, Street='Via Nazionale 22', City='Rome', Country='Italy', Stars=4" >/dev/null \
  && echo "  Inserted: Hotel Artemide" || echo "  WARNING: Hotel Artemide failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Fairmont Le Manoir', Type='Historic', Phone='+33-1-46-31-98-00', Latitude=48.8197, Longitude=2.2999, Street='Route de Montrouge 1', City='Paris', Country='France', Stars=4" >/dev/null \
  && echo "  Inserted: Fairmont Le Manoir" || echo "  WARNING: Fairmont Le Manoir failed"

orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Melia Berlin', Type='Business', Phone='+49-30-20607-0', Latitude=52.5203, Longitude=13.3867, Street='Friedrichstrasse 103', City='Berlin', Country='Germany', Stars=4" >/dev/null \
  && echo "  Inserted: Melia Berlin" || echo "  WARNING: Melia Berlin failed"

# Remove Italian null-Country/null-Stars records left from DemoDB checkpoint (~1154 records).
# Must use DELETE VERTEX (not DELETE FROM) because Italian hotels have connected edges.
echo "Removing Italian null-Country records from Hotels..."
orientdb_sql "demodb" "DELETE VERTEX Hotels WHERE Country IS NULL" >/dev/null 2>&1 || true
sleep 2

# Verify count
hotel_count=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "?")
echo "Hotels in DB after setup: ${hotel_count} (expected 15)"

# Capture baseline hotel counts per country for anti-gaming check
python3 << 'PYEOF'
import json, urllib.request, base64

auth = base64.b64encode(b"root:GymAnything123!").decode()
headers = {"Authorization": f"Basic {auth}", "Content-Type": "application/json"}

def sql(cmd):
    req = urllib.request.Request(
        "http://localhost:2480/command/demodb/sql",
        data=json.dumps({"command": cmd}).encode(),
        headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read())
    except Exception:
        return {}

rows = sql("SELECT Country, COUNT(*) as cnt FROM Hotels GROUP BY Country").get("result", [])
baseline = {r.get("Country"): int(r.get("cnt", 0)) for r in rows if r.get("Country")}

with open("/tmp/aggregate_hotel_country_metrics_baseline.json", "w") as f:
    json.dump({"country_hotel_counts": baseline, "metrics_count": 0}, f, indent=2)

print("Baseline captured:", json.dumps(baseline, indent=2))
PYEOF

date +%s > /tmp/task_start_timestamp

kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8
take_screenshot /tmp/task_start_aggregate_hotel_country_metrics.png

echo "=== Setup complete: aggregate_hotel_country_metrics ==="
