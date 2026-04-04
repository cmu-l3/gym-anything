#!/bin/bash
set -e
echo "=== Setting up Spatial Grid Indexing Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 60

# --- Clean State Setup ---
# We need to ensure GeographicZone and InZone do not exist from a previous run.
echo "Ensuring clean schema state..."

# Check if InZone edge class exists and drop it
if orientdb_class_exists "demodb" "InZone"; then
    echo "Dropping existing InZone class..."
    orientdb_sql "demodb" "DROP CLASS InZone UNSAFE" > /dev/null 2>&1 || true
fi

# Check if GeographicZone vertex class exists and drop it
if orientdb_class_exists "demodb" "GeographicZone"; then
    echo "Dropping existing GeographicZone class..."
    orientdb_sql "demodb" "DROP CLASS GeographicZone UNSAFE" > /dev/null 2>&1 || true
fi

# Ensure Hotel data exists (using count check)
HOTEL_COUNT=$(curl -s -X POST -u "${ORIENTDB_AUTH}" \
    -H "Content-Type: application/json" \
    -d '{"command":"SELECT COUNT(*) as cnt FROM Hotels"}' \
    "${ORIENTDB_URL}/command/demodb/sql" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

echo "Current Hotel count: $HOTEL_COUNT"

if [ "$HOTEL_COUNT" -lt 5 ]; then
    echo "WARNING: Hotel data seems missing or low. Re-seeding might be required."
    # We rely on the environment's post_start hook to seed, but we log this for debugging.
fi

# Remove any pre-existing report file
rm -f /home/ga/zone_density_report.txt

# --- Application Setup ---
# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="