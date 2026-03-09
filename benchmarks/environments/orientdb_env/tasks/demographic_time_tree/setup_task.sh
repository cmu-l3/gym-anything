#!/bin/bash
set -e
echo "=== Setting up demographic_time_tree task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running and ready
wait_for_orientdb 120

# Clean up any previous runs (Idempotency)
echo "Cleaning up previous schema if exists..."
# We drop strictly in order to avoid constraint violations, though UNSAFE handles most
orientdb_sql "demodb" "DROP CLASS BornIn UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS HasMonth UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS Month UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS Year UNSAFE" > /dev/null 2>&1 || true

# Ensure Profiles exist (standard setup should handle this, but verification is good)
echo "Verifying Profiles data..."
PROFILE_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Profiles" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', [{}])[0].get('count', 0))" 2>/dev/null || echo "0")
echo "Initial Profile count: $PROFILE_COUNT"

if [ "$PROFILE_COUNT" -lt 5 ]; then
    echo "WARNING: Profiles missing or low count. Re-seeding..."
    python3 /workspace/scripts/seed_demodb.py
fi

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="