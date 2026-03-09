#!/bin/bash
# Setup for create_solution_article task
# Ensures SDP is running and records initial state

set -e
echo "=== Setting up Create Solution Article task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure SDP is running (this waits for install if needed)
ensure_sdp_running

# 2. Record start time for anti-gaming (timestamp verification)
date +%s > /tmp/task_start_time.txt

# 3. Record initial number of solutions to detect new creations
# We query the 'Solution' table. 
# Note: Table names in SDP Postgres are often lowercase or mixed. We try generic standard.
echo "Recording initial solution count..."
INITIAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM Solution;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_solution_count.txt
echo "Initial solution count: $INITIAL_COUNT"

# 4. Open Firefox to the home page
# We don't navigate directly to Solutions to force the agent to find it
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="