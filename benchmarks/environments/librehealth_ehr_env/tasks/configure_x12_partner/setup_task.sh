#!/bin/bash
set -e
echo "=== Setting up Configure X12 Partner Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth EHR is running
wait_for_librehealth 60

# Clean up any previous attempts (Anti-gaming / Idempotency)
echo "Cleaning up previous 'Availity' records..."
librehealth_query "DELETE FROM x12_partners WHERE name LIKE '%Availity%'" 2>/dev/null || true

# Record initial state (Anti-gaming)
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM x12_partners" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial x12_partners count: $INITIAL_COUNT"

# Restart Firefox at login page to ensure clean UI state
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Credentials: admin / password"