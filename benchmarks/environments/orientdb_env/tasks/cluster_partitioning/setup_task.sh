#!/bin/bash
echo "=== Setting up Cluster Partitioning Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 120

# Ensure demodb exists
if ! orientdb_db_exists "demodb"; then
    echo "Creating demodb..."
    # The setup_orientdb.sh script usually handles this, but we double check
    # We can trigger the seeder manually if needed
    python3 /workspace/scripts/seed_demodb.py
fi

# Reset State: Clean up previous run artifacts
# If clusters exist, we need to drop them. 
# WARNING: Dropping clusters deletes data. We must ensure data exists afterwards.
echo "Cleaning up any previous partitioning..."
orientdb_sql "demodb" "DROP CLUSTER hotels_europe UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "ALTER CLASS Hotels REMOVECLUSTER hotels_europe" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLUSTER hotels_americas UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "ALTER CLASS Hotels REMOVECLUSTER hotels_americas" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLUSTER hotels_asiapacific UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "ALTER CLASS Hotels REMOVECLUSTER hotels_asiapacific" >/dev/null 2>&1 || true

# Remove report file
rm -f /home/ga/partitioning_report.txt

# Verify Data Health
# Check if Hotels have data. If we dropped clusters containing data in a previous run,
# the Hotels class might be empty now.
HOTEL_COUNT_JSON=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels")
HOTEL_COUNT=$(echo "$HOTEL_COUNT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

echo "Current Hotel count: $HOTEL_COUNT"

if [ "$HOTEL_COUNT" -lt 10 ]; then
    echo "Data missing or corrupted. Reseeding demodb..."
    # Truncate to avoid duplicates if partial data exists
    orientdb_sql "demodb" "TRUNCATE CLASS Hotels UNSAFE" >/dev/null 2>&1 || true
    python3 /workspace/scripts/seed_demodb.py
    
    # Verify again
    HOTEL_COUNT_JSON=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels")
    HOTEL_COUNT=$(echo "$HOTEL_COUNT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    echo "Refreshed Hotel count: $HOTEL_COUNT"
fi

# Save initial count for verification
echo "$HOTEL_COUNT" > /tmp/initial_hotel_count.txt

# Launch Firefox to OrientDB Studio
echo "Launching Firefox to OrientDB Studio..."
launch_firefox "http://localhost:2480/studio/index.html" 10

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="