#!/bin/bash
# setup_task.sh - Pre-task setup for create_fleet_monitoring_views

set -e
echo "=== Setting up create_fleet_monitoring_views task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge to be ready (ensures DB is initialized)
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Prepare environment directories
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Clean up any previous artifacts
rm -f /home/ga/Documents/dashboard_views.sql
rm -f /home/ga/Documents/dashboard_views_output.txt
rm -f /tmp/task_result.json

# 4. Reset Database State (Drop views if they exist from previous runs)
DB_PATH="/opt/aerobridge/aerobridge.sqlite3"
if [ -f "$DB_PATH" ]; then
    echo "Cleaning up existing views in $DB_PATH..."
    sqlite3 "$DB_PATH" "DROP VIEW IF EXISTS v_fleet_overview;"
    sqlite3 "$DB_PATH" "DROP VIEW IF EXISTS v_operator_fleet_size;"
    sqlite3 "$DB_PATH" "DROP VIEW IF EXISTS v_personnel_directory;"
else
    echo "ERROR: Database not found at $DB_PATH"
    exit 1
fi

# 5. Record Initial State
date +%s > /tmp/task_start_time
# Record list of existing views (should be empty of our target views)
sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='view';" > /tmp/initial_views.txt

# 6. Launch Firefox to Admin Panel (helpful for agent to see data visually if they want)
# Using standard launch_firefox utility if available, else manual
echo "Launching Firefox..."
if type launch_firefox >/dev/null 2>&1; then
    launch_firefox "http://localhost:8000/admin/"
else
    pkill -9 -f firefox 2>/dev/null || true
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8000/admin/' &"
    sleep 5
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Database: $DB_PATH"
echo "Target: Create SQL views v_fleet_overview, v_operator_fleet_size, v_personnel_directory"