#!/bin/bash
set -e
echo "=== Setting up Create BP Group and Customer Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up stale data to ensure the agent actually performs the task
echo "Cleaning up any previous attempts..."

# Define cleanup queries
# We attempt to delete the specific BP and Group if they exist from a previous run.
# Deleting BP first to remove dependency on Group.
idempiere_query "DELETE FROM c_bpartner WHERE value='CITY_BOTANICAL' AND ad_client_id=11" 2>/dev/null || true
idempiere_query "DELETE FROM c_bp_group WHERE value='BotGarden' AND ad_client_id=11" 2>/dev/null || true

# 3. Ensure Firefox is running and logged into iDempiere
echo "Ensuring iDempiere is open..."
navigate_to_dashboard

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot captured."

echo "=== Setup complete ==="