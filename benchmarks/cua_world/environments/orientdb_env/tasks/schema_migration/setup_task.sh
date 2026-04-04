#!/bin/bash
set -e
echo "=== Setting up Schema Migration task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 60

# Ensure demodb exists and is populated
if ! orientdb_db_exists "demodb"; then
    echo "demodb missing, running seeder..."
    python3 /workspace/scripts/seed_demodb.py
fi

echo "Resetting schema state for task..."

# 1. Drop properties if they exist
orientdb_sql "demodb" "DROP PROPERTY Restaurants.Rating FORCE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP PROPERTY Hotels.Capacity FORCE" >/dev/null 2>&1 || true

# 2. Reset constraints on Hotels.Name
orientdb_sql "demodb" "ALTER PROPERTY Hotels.Name MANDATORY false" >/dev/null 2>&1 || true

# 3. Reset constraints on Hotels.Stars
orientdb_sql "demodb" "ALTER PROPERTY Hotels.Stars MIN null" >/dev/null 2>&1 || true
orientdb_sql "demodb" "ALTER PROPERTY Hotels.Stars MAX null" >/dev/null 2>&1 || true

# 4. Drop composite index if exists
orientdb_sql "demodb" "DROP INDEX Hotels_Country_Stars_idx" >/dev/null 2>&1 || true

# 5. Ensure data exists for backfill verification
# Check if we have hotels and restaurants
HOTEL_COUNT=$(orientdb_query "demodb" "SELECT count(*) FROM Hotels" | jq '.result[0].count' 2>/dev/null || echo "0")
REST_COUNT=$(orientdb_query "demodb" "SELECT count(*) FROM Restaurants" | jq '.result[0].count' 2>/dev/null || echo "0")

if [ "$HOTEL_COUNT" -lt 5 ] || [ "$REST_COUNT" -lt 5 ]; then
    echo "Insufficient data (Hotels: $HOTEL_COUNT, Restaurants: $REST_COUNT). Reseeding..."
    python3 /workspace/scripts/seed_demodb.py
fi

# Record initial counts to ensure agent doesn't just delete data
echo "$HOTEL_COUNT" > /tmp/initial_hotel_count.txt
echo "$REST_COUNT" > /tmp/initial_rest_count.txt

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="