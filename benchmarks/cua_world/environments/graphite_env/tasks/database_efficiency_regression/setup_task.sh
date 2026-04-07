#!/bin/bash
echo "=== Setting up database_efficiency_regression task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/database_efficiency_regression_result.json 2>/dev/null || true
rm -f /tmp/database_efficiency_regression_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'ORM Efficiency Analysis'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'ORM Efficiency Analysis' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist in Graphite
echo "Checking for required metrics..."
for metric in "servers.load_balancer.requests.count" \
              "servers.rds_database.cpu.utilization"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp for verification
date +%s > /tmp/database_efficiency_regression_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot showing clean workspace
take_screenshot /tmp/database_efficiency_regression_start_screenshot.png

echo "=== database_efficiency_regression setup complete ==="