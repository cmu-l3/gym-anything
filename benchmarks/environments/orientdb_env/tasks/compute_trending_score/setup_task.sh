#!/bin/bash
set -e
echo "=== Setting up compute_trending_score task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# Connect to demodb and clean up any previous run artifacts
echo "Preparing database state..."
# Drop TrendingScore property if it exists to ensure agent starts fresh
orientdb_sql "demodb" "DROP PROPERTY Hotels.TrendingScore FORCE" > /dev/null 2>&1 || true
sleep 2

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="