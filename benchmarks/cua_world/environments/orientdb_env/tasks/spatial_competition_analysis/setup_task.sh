#!/bin/bash
echo "=== Setting up Spatial Competition Analysis Task ==="

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 120

# --- PREPARE DATA ---
# We need to inject specific "competitor" hotels to create a known ground truth for the verification.
# Base data:
# - Hotel Artemide (Rome): 41.8981, 12.4989
# - The Savoy (London): 51.5099, -0.1201
# - Park Hyatt Tokyo: 35.6858, 139.6909

echo "Injecting competitor data for verification scenario..."

# Rome Cluster (Artemide + 3 competitors within 2km)
# 1. Competitor A (~500m away)
orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Competitor Rome A', City='Rome', Country='Italy', Latitude=41.9020, Longitude=12.5000, Stars=3, Type='Budget'" > /dev/null
# 2. Competitor B (~1.1km away)
orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Competitor Rome B', City='Rome', Country='Italy', Latitude=41.8900, Longitude=12.4900, Stars=4, Type='Business'" > /dev/null
# 3. Competitor C (~1.8km away)
orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Competitor Rome C', City='Rome', Country='Italy', Latitude=41.9100, Longitude=12.5100, Stars=5, Type='Luxury'" > /dev/null
# 4. Competitor D (OUTSIDE radius, ~3km away) - Should NOT be counted
orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Competitor Rome Distant', City='Rome', Country='Italy', Latitude=41.9300, Longitude=12.5300, Stars=3, Type='Budget'" > /dev/null

# London Cluster (Savoy + 2 competitors within 2km)
# 1. Competitor A (~800m away)
orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Competitor London A', City='London', Country='United Kingdom', Latitude=51.5150, Longitude=-0.1150, Stars=5, Type='Luxury'" > /dev/null
# 2. Competitor B (~1.5km away)
orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Competitor London B', City='London', Country='United Kingdom', Latitude=51.5000, Longitude=-0.1300, Stars=4, Type='Boutique'" > /dev/null

# Tokyo Cluster (Park Hyatt + 0 competitors)
# No insertions needed. Ensure no random hotels are nearby in the seed.

# Reset any previous attempts (drop property/index/function if they exist)
echo "Cleaning previous state..."
orientdb_sql "demodb" "DROP INDEX Hotels.Latitude IF EXISTS" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX Hotels.Longitude IF EXISTS" > /dev/null 2>&1 || true
# Note: SPATIAL index name might vary, we'll check schema later
orientdb_sql "demodb" "DROP PROPERTY Hotels.CompetitionScore IF EXISTS" > /dev/null 2>&1 || true
# Drop function via REST API (SQL DROP FUNCTION available in newer versions, checking both)
curl -s -X POST -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/command/demodb/sql" \
    -d '{"command": "DROP FUNCTION CalculateCompetition"}' \
    -H "Content-Type: application/json" > /dev/null 2>&1 || true

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 8

# Initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="