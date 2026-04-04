#!/bin/bash
set -euo pipefail

echo "=== Setup: link_nearby_restaurants_and_attractions ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh
wait_for_orientdb 90

rm -f /tmp/link_nearby_restaurants_and_attractions_result.json \
      /tmp/link_nearby_restaurants_and_attractions_baseline.json \
      /tmp/task_start_timestamp 2>/dev/null || true

# Remove prior ProximityLink and RecommendationManifest artifacts
orientdb_sql "demodb" "DELETE EDGE ProximityLink" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS ProximityLink UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX RecommendationManifest" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX RecommendationManifest.City" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS RecommendationManifest UNSAFE" >/dev/null 2>&1 || true

# Seed canonical restaurants and attractions.
# Strategy: DROP Id UNIQUE indexes first (same issue as Hotels.Id: built-in OrientDB DemoDB
# Italian records have non-null OSM Id values in UNIQUE indexes; canonical inserts don't
# specify Id, so INSERT #2 fails with UNIQUE violation). Then INSERT canonical records,
# then DELETE VERTEX the Italian null-Country records (DELETE VERTEX required because
# Italian records have connected edges; DELETE FROM fails for vertices with edges).
echo "Dropping Id UNIQUE indexes to allow null-Id canonical inserts..."
orientdb_sql "demodb" "DROP INDEX Hotels.Id" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX Restaurants.Id" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX Attractions.Id" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX ArchaeologicalSites.Id" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX Castles.Id" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX Monuments.Id" >/dev/null 2>&1 || true

echo "Inserting 7 canonical restaurants..."

orientdb_sql "demodb" "INSERT INTO Restaurants SET Name='Da Enzo al 29', Type='Traditional Italian', Phone='+39-06-581-2260', Latitude=41.8902, Longitude=12.4672, Street='Via dei Vascellari 29', City='Rome', Country='Italy'" >/dev/null \
  && echo "  Inserted: Da Enzo al 29" || echo "  WARNING: Da Enzo al 29 failed"

orientdb_sql "demodb" "INSERT INTO Restaurants SET Name='Lorenz Adlon Esszimmer', Type='French Contemporary', Phone='+49-30-2261-1960', Latitude=52.5162, Longitude=13.3777, Street='Unter den Linden 77', City='Berlin', Country='Germany'" >/dev/null \
  && echo "  Inserted: Lorenz Adlon Esszimmer" || echo "  WARNING: Lorenz Adlon Esszimmer failed"

orientdb_sql "demodb" "INSERT INTO Restaurants SET Name='Le Cinq', Type='French Gastronomic', Phone='+33-1-49-52-71-54', Latitude=48.8728, Longitude=2.3091, Street='Avenue George V 31', City='Paris', Country='France'" >/dev/null \
  && echo "  Inserted: Le Cinq" || echo "  WARNING: Le Cinq failed"

orientdb_sql "demodb" "INSERT INTO Restaurants SET Name='Sketch', Type='Contemporary British', Phone='+44-20-7659-4500', Latitude=51.5123, Longitude=-0.1432, Street='9 Conduit Street', City='London', Country='United Kingdom'" >/dev/null \
  && echo "  Inserted: Sketch" || echo "  WARNING: Sketch failed"

orientdb_sql "demodb" "INSERT INTO Restaurants SET Name='Per Se', Type='New American', Phone='+1-212-823-9335', Latitude=40.7687, Longitude=-73.9830, Street='Columbus Circle 10', City='New York', Country='United States'" >/dev/null \
  && echo "  Inserted: Per Se" || echo "  WARNING: Per Se failed"

orientdb_sql "demodb" "INSERT INTO Restaurants SET Name='Spondi', Type='French Mediterranean', Phone='+30-210-756-4021', Latitude=37.9781, Longitude=23.7467, Street='Pyrronos 5', City='Athens', Country='Greece'" >/dev/null \
  && echo "  Inserted: Spondi" || echo "  WARNING: Spondi failed"

orientdb_sql "demodb" "INSERT INTO Restaurants SET Name='Tickets', Type='Catalan Avant-Garde', Phone='+34-93-292-4254', Latitude=41.3762, Longitude=2.1614, Street='Avinguda Parallel 164', City='Barcelona', Country='Spain'" >/dev/null \
  && echo "  Inserted: Tickets" || echo "  WARNING: Tickets failed"

echo "Inserting 8 canonical attractions..."

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Colosseum', City='Rome', Country='Italy', Latitude=41.8902, Longitude=12.4922" >/dev/null \
  && echo "  Inserted: Colosseum" || echo "  WARNING: Colosseum failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Brandenburg Gate', City='Berlin', Country='Germany', Latitude=52.5163, Longitude=13.3777" >/dev/null \
  && echo "  Inserted: Brandenburg Gate" || echo "  WARNING: Brandenburg Gate failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Eiffel Tower', City='Paris', Country='France', Latitude=48.8584, Longitude=2.2945" >/dev/null \
  && echo "  Inserted: Eiffel Tower" || echo "  WARNING: Eiffel Tower failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Big Ben', City='London', Country='United Kingdom', Latitude=51.5007, Longitude=-0.1246" >/dev/null \
  && echo "  Inserted: Big Ben" || echo "  WARNING: Big Ben failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Statue of Liberty', City='New York', Country='United States', Latitude=40.6892, Longitude=-74.0445" >/dev/null \
  && echo "  Inserted: Statue of Liberty" || echo "  WARNING: Statue of Liberty failed"

orientdb_sql "demodb" "INSERT INTO ArchaeologicalSites SET Name='Acropolis of Athens', City='Athens', Country='Greece', Latitude=37.9715, Longitude=23.7257" >/dev/null \
  && echo "  Inserted: Acropolis of Athens" || echo "  WARNING: Acropolis of Athens failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Parthenon', City='Athens', Country='Greece', Latitude=37.9715, Longitude=23.7267" >/dev/null \
  && echo "  Inserted: Parthenon" || echo "  WARNING: Parthenon failed"

orientdb_sql "demodb" "INSERT INTO Monuments SET Name='Sagrada Familia', City='Barcelona', Country='Spain', Latitude=41.4036, Longitude=2.1744" >/dev/null \
  && echo "  Inserted: Sagrada Familia" || echo "  WARNING: Sagrada Familia failed"

# Remove Italian null-Country records from Restaurants and all Attractions subclasses.
# Must use DELETE VERTEX (not DELETE FROM) because Italian records have connected edges.
echo "Removing Italian null-Country records from Restaurants and Attractions..."
orientdb_sql "demodb" "DELETE VERTEX Restaurants WHERE Country IS NULL" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX ArchaeologicalSites WHERE Country IS NULL" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX Castles WHERE Country IS NULL" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX Monuments WHERE Country IS NULL" >/dev/null 2>&1 || true
sleep 2

# Verify counts
rest_count=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Restaurants" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "?")
attr_count=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Attractions" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "?")
echo "Restaurants: ${rest_count} (expected 7), Attractions: ${attr_count} (expected 8)"

# Baseline snapshot
cat > /tmp/link_nearby_restaurants_and_attractions_baseline.json << 'EOF'
{
  "proximity_edge_count": 0,
  "manifest_row_count": 0
}
EOF

date +%s > /tmp/task_start_timestamp

kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8
take_screenshot /tmp/task_start_link_nearby_restaurants_and_attractions.png

echo "=== Setup complete: link_nearby_restaurants_and_attractions ==="
