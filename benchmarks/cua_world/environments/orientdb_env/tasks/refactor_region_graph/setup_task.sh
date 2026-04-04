#!/bin/bash
set -e
echo "=== Setting up Refactor Region Graph Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# === CLEANUP & PREPARATION ===
# We need to ensure the starting state is "flat":
# - Countries exist with 'Type' property
# - Regions class does NOT exist
# - InRegion edge class does NOT exist

echo "Resetting database state..."

# Drop classes if they exist from previous runs (ignore errors if they don't)
orientdb_sql "demodb" "DROP CLASS InRegion UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS Regions UNSAFE" > /dev/null 2>&1 || true

# Verify Countries exist and have Type property
echo "Verifying initial data..."
COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Countries WHERE Type IS NOT NULL" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

echo "Found $COUNT countries with Type property."

if [ "$COUNT" -lt 5 ]; then
    echo "WARNING: Initial data seems missing. Re-seeding might be required."
    # In a real scenario, we might trigger the seeder here, but the env setup usually handles it.
fi

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="