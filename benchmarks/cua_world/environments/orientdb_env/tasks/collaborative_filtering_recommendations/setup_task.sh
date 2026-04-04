#!/bin/bash
echo "=== Setting up Collaborative Filtering Task ==="
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 60

# Clean state: Drop classes if they exist from previous runs to ensure fresh start
echo "Cleaning up previous state..."
orientdb_sql "demodb" "DROP CLASS HasRecommendation UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS Recommendations UNSAFE" > /dev/null 2>&1 || true

# Remove query file
rm -f /home/ga/recommendation_query.sql

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="