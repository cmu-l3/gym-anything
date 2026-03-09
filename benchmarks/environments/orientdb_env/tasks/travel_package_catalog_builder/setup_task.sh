#!/bin/bash
echo "=== Setting up Travel Package Catalog Builder task ==="
set -e

# Source utilities
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running and ready
wait_for_orientdb 120

echo "Resetting database state..."

# 1. Clean up 'Packages' and 'IncludesItem' if they exist from previous runs
orientdb_sql "demodb" "DELETE VERTEX Packages UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS Packages UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS IncludesItem UNSAFE" >/dev/null 2>&1 || true

# 2. Clean up specific 'Attractions' if they exist
for name in "Colosseum" "Eiffel Tower" "Tokyo Tower"; do
    orientdb_sql "demodb" "DELETE VERTEX Attractions WHERE Name='$name'" >/dev/null 2>&1 || true
done

# 3. Drop 'Price' property from Hotels, Restaurants, Attractions if they exist
# Note: DROP PROPERTY is not always "unsafe", but modifying schema on live data is sensitive.
# We try to drop them to force the agent to create them.
orientdb_sql "demodb" "DROP PROPERTY Hotels.Price FORCE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP PROPERTY Restaurants.Price FORCE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP PROPERTY Attractions.Price FORCE" >/dev/null 2>&1 || true

# 4. Ensure Attractions class exists (it's part of seed but good to ensure)
if ! orientdb_class_exists "demodb" "Attractions"; then
    orientdb_sql "demodb" "CREATE CLASS Attractions EXTENDS V" >/dev/null 2>&1 || true
    orientdb_sql "demodb" "CREATE PROPERTY Attractions.Name STRING" >/dev/null 2>&1 || true
    orientdb_sql "demodb" "CREATE PROPERTY Attractions.City STRING" >/dev/null 2>&1 || true
fi

# 5. Ensure the Hotels and Restaurants we need actually exist (they should from seed_demodb.py)
# We won't re-seed the whole thing, but we check if DB is empty.
# If Hotels count is 0, we might need to run the seeder.
HOTEL_COUNT=$(curl -s -X POST -u "${ORIENTDB_AUTH}" \
    -H "Content-Type: application/json" \
    -d '{"command":"SELECT COUNT(*) as cnt FROM Hotels"}' \
    "${ORIENTDB_URL}/command/demodb/sql" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

if [ "$HOTEL_COUNT" -eq "0" ]; then
    echo "Database appears empty. Running seeder..."
    python3 /workspace/scripts/seed_demodb.py
fi

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="