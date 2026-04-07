#!/bin/bash
echo "=== Setting up db_saturation_impact_overlay task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/db_saturation_impact_overlay_result.json 2>/dev/null || true
rm -f /tmp/db_saturation_impact_overlay_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'DB Saturation Impact'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'DB Saturation Impact' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist
echo "Checking for required metrics..."
for metric in "servers.rds_database.cpu.utilization" \
              "servers.load_balancer.requests.count"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/db_saturation_impact_overlay_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/db_saturation_impact_overlay_start_screenshot.png

echo "=== db_saturation_impact_overlay setup complete ==="