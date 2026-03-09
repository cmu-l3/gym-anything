#!/bin/bash
set -euo pipefail

echo "=== Setup: backfill_attraction_visit_counts ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh
wait_for_orientdb 90

rm -f /tmp/backfill_attraction_visit_counts_result.json \
      /tmp/backfill_attraction_visit_counts_baseline.json \
      /tmp/task_start_timestamp 2>/dev/null || true

sql_count() {
    local query="$1"
    orientdb_sql "demodb" "$query" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0"
}

ensure_profile() {
    local email="$1" name="$2" surname="$3" gender="$4" bday="$5" nationality="$6"
    local cnt
    cnt=$(sql_count "SELECT COUNT(*) as cnt FROM Profiles WHERE Email='${email}'")
    if [ "$cnt" = "0" ]; then
        orientdb_sql "demodb" "INSERT INTO Profiles SET Email='${email}', Name='${name}', Surname='${surname}', Gender='${gender}', Birthday='${bday}', Nationality='${nationality}'" >/dev/null 2>&1 || true
    fi
}

# Ensure cohort profiles exist
ensure_profile "kai.yamamoto@example.com"    "Kai"    "Yamamoto"   "Male"   "1996-08-16" "Japanese"
ensure_profile "piet.vanderberg@example.com" "Piet"   "Vanderberg" "Male"   "1980-02-14" "Dutch"
ensure_profile "carlos.lopez@example.com"    "Carlos" "Lopez"      "Male"   "1987-06-07" "Mexican"
ensure_profile "thomas.schafer@example.com"  "Thomas" "Schafer"    "Male"   "1970-05-05" "German"

# Remove prior VisitCount property if it exists (for clean state)
orientdb_sql "demodb" "DROP PROPERTY Attractions.VisitCount" >/dev/null 2>&1 || true

# Remove prior AttractionVisitAudit artifacts
orientdb_sql "demodb" "DELETE VERTEX AttractionVisitAudit" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX AttractionVisitAudit.AuditBatch" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS AttractionVisitAudit UNSAFE" >/dev/null 2>&1 || true

# Seed the 14 canonical attractions.
# Strategy: DROP Attractions subclass Id UNIQUE indexes (same issue as Hotels.Id: the
# built-in OrientDB DemoDB Italian attractions have non-null OSM Id values in UNIQUE
# indexes; canonical inserts don't specify Id, so INSERT #2 fails with UNIQUE violation).
# Then INSERT canonical attractions, then DELETE VERTEX the Italian null-Country records
# (DELETE VERTEX required because Italian attractions have connected edges).
echo "Dropping Attractions subclass Id UNIQUE indexes to allow null-Id canonical inserts..."
orientdb_sql "demodb" "DROP INDEX Attractions.Id" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX ArchaeologicalSites.Id" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX Castles.Id" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX Monuments.Id" >/dev/null 2>&1 || true

echo "Inserting 14 canonical attractions..."

# --- 5 TARGET attractions (will receive HasVisited edges) ---
orientdb_sql "demodb" "INSERT INTO ArchaeologicalSites SET Name='Acropolis of Athens', City='Athens', Country='Greece', Latitude=37.9715, Longitude=23.7257" >/dev/null \
  && echo "  Inserted: Acropolis of Athens" || echo "  WARNING: Acropolis of Athens failed"

orientdb_sql "demodb" "INSERT INTO Castles SET Name='Neuschwanstein Castle', City='Schwangau', Country='Germany', Latitude=47.5576, Longitude=10.7498" >/dev/null \
  && echo "  Inserted: Neuschwanstein Castle" || echo "  WARNING: Neuschwanstein Castle failed"

orientdb_sql "demodb" "INSERT INTO Castles SET Name='Edinburgh Castle', City='Edinburgh', Country='United Kingdom', Latitude=55.9486, Longitude=-3.1999" >/dev/null \
  && echo "  Inserted: Edinburgh Castle" || echo "  WARNING: Edinburgh Castle failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Sagrada Familia', City='Barcelona', Country='Spain', Latitude=41.4036, Longitude=2.1744" >/dev/null \
  && echo "  Inserted: Sagrada Familia" || echo "  WARNING: Sagrada Familia failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Brandenburg Gate', City='Berlin', Country='Germany', Latitude=52.5163, Longitude=13.3777" >/dev/null \
  && echo "  Inserted: Brandenburg Gate" || echo "  WARNING: Brandenburg Gate failed"

# --- 9 zero-visit attractions ---
orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Colosseum', City='Rome', Country='Italy', Latitude=41.8902, Longitude=12.4922" >/dev/null \
  && echo "  Inserted: Colosseum" || echo "  WARNING: Colosseum failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Eiffel Tower', City='Paris', Country='France', Latitude=48.8584, Longitude=2.2945" >/dev/null \
  && echo "  Inserted: Eiffel Tower" || echo "  WARNING: Eiffel Tower failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Statue of Liberty', City='New York', Country='United States', Latitude=40.6892, Longitude=-74.0445" >/dev/null \
  && echo "  Inserted: Statue of Liberty" || echo "  WARNING: Statue of Liberty failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Big Ben', City='London', Country='United Kingdom', Latitude=51.5007, Longitude=-0.1246" >/dev/null \
  && echo "  Inserted: Big Ben" || echo "  WARNING: Big Ben failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Parthenon', City='Athens', Country='Greece', Latitude=37.9715, Longitude=23.7257" >/dev/null \
  && echo "  Inserted: Parthenon" || echo "  WARNING: Parthenon failed"

orientdb_sql "demodb" "INSERT INTO ArchaeologicalSites SET Name='Pompeii', City='Pompeii', Country='Italy', Latitude=40.7489, Longitude=14.4989" >/dev/null \
  && echo "  Inserted: Pompeii" || echo "  WARNING: Pompeii failed"

orientdb_sql "demodb" "INSERT INTO ArchaeologicalSites SET Name='Stonehenge', City='Amesbury', Country='United Kingdom', Latitude=51.1789, Longitude=-1.8262" >/dev/null \
  && echo "  Inserted: Stonehenge" || echo "  WARNING: Stonehenge failed"

orientdb_sql "demodb" "INSERT INTO Castles SET Name='Bran Castle', City='Bran', Country='Romania', Latitude=45.5152, Longitude=25.3671" >/dev/null \
  && echo "  Inserted: Bran Castle" || echo "  WARNING: Bran Castle failed"

orientdb_sql "demodb" "INSERT INTO Castles SET Name='Chateau de Chambord', City='Chambord', Country='France', Latitude=47.6161, Longitude=1.5170" >/dev/null \
  && echo "  Inserted: Chateau de Chambord" || echo "  WARNING: Chateau de Chambord failed"

# Remove Italian null-Country records from each Attractions subclass.
# Must use DELETE VERTEX (not DELETE FROM) because Italian attractions have connected edges.
echo "Removing Italian null-Country records from Attractions subclasses..."
orientdb_sql "demodb" "DELETE VERTEX ArchaeologicalSites WHERE Country IS NULL" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX Castles WHERE Country IS NULL" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX Monuments WHERE Country IS NULL" >/dev/null 2>&1 || true
sleep 2

# Remove all prior HasVisited edges (DemoDB demo data + any stale edges from deleted attractions).
echo "Removing all HasVisited edges..."
orientdb_sql "demodb" "DELETE EDGE HasVisited" >/dev/null 2>&1 || true
sleep 1

# Verify count
attr_count=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Attractions" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "?")
echo "Attractions in DB after setup: ${attr_count} (expected 14)"

# Create task-specific HasVisited edges.
# Using parent Attractions class (polymorphic) to find records regardless of subclass.
# LIMIT 1 prevents duplicate edges if a name appears more than once.

# kai.yamamoto -> Acropolis of Athens
orientdb_sql "demodb" "CREATE EDGE HasVisited FROM (SELECT FROM Profiles WHERE Email='kai.yamamoto@example.com') TO (SELECT FROM Attractions WHERE Name='Acropolis of Athens' LIMIT 1)" >/dev/null 2>&1 || true

# kai.yamamoto -> Neuschwanstein Castle
orientdb_sql "demodb" "CREATE EDGE HasVisited FROM (SELECT FROM Profiles WHERE Email='kai.yamamoto@example.com') TO (SELECT FROM Attractions WHERE Name='Neuschwanstein Castle' LIMIT 1)" >/dev/null 2>&1 || true

# piet.vanderberg -> Acropolis of Athens (second visitor → count=2)
orientdb_sql "demodb" "CREATE EDGE HasVisited FROM (SELECT FROM Profiles WHERE Email='piet.vanderberg@example.com') TO (SELECT FROM Attractions WHERE Name='Acropolis of Athens' LIMIT 1)" >/dev/null 2>&1 || true

# piet.vanderberg -> Sagrada Familia
orientdb_sql "demodb" "CREATE EDGE HasVisited FROM (SELECT FROM Profiles WHERE Email='piet.vanderberg@example.com') TO (SELECT FROM Attractions WHERE Name='Sagrada Familia' LIMIT 1)" >/dev/null 2>&1 || true

# carlos.lopez -> Edinburgh Castle
orientdb_sql "demodb" "CREATE EDGE HasVisited FROM (SELECT FROM Profiles WHERE Email='carlos.lopez@example.com') TO (SELECT FROM Attractions WHERE Name='Edinburgh Castle' LIMIT 1)" >/dev/null 2>&1 || true

# thomas.schafer -> Neuschwanstein Castle (second visitor → count=2)
orientdb_sql "demodb" "CREATE EDGE HasVisited FROM (SELECT FROM Profiles WHERE Email='thomas.schafer@example.com') TO (SELECT FROM Attractions WHERE Name='Neuschwanstein Castle' LIMIT 1)" >/dev/null 2>&1 || true

# thomas.schafer -> Brandenburg Gate
orientdb_sql "demodb" "CREATE EDGE HasVisited FROM (SELECT FROM Profiles WHERE Email='thomas.schafer@example.com') TO (SELECT FROM Attractions WHERE Name='Brandenburg Gate' LIMIT 1)" >/dev/null 2>&1 || true

# Verify edge creation
edge_count=$(sql_count "SELECT COUNT(*) as cnt FROM HasVisited")
echo "HasVisited edges created: ${edge_count} (expected 7)"

total_attractions=$(sql_count "SELECT COUNT(*) as cnt FROM Attractions")
echo "Total attractions: ${total_attractions} (expected 14)"

cat > /tmp/backfill_attraction_visit_counts_baseline.json << EOF
{
  "has_visited_edge_count": ${edge_count},
  "total_attractions": ${total_attractions},
  "visit_count_property_exists": false,
  "audit_row_count": 0
}
EOF

date +%s > /tmp/task_start_timestamp

kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8
take_screenshot /tmp/task_start_backfill_attraction_visit_counts.png

echo "=== Setup complete: backfill_attraction_visit_counts ==="
