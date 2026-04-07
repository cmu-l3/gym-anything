#!/bin/bash
echo "=== Setting up incident_blast_radius_visualization task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming verification
date +%s > /tmp/incident_blast_radius_visualization_start_ts

# Ensure Graphite environment is ready for testing
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/incident_blast_radius_visualization_result.json 2>/dev/null || true
rm -f /tmp/incident_blast_radius_visualization_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure a clean starting state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Post-Incident Blast Radius'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Post-Incident Blast Radius' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics actually exist in the Carbon store
echo "Checking for required metrics..."
for metric in "servers.rds_database.cpu.utilization" \
              "servers.web_traffic.speed_sensor_1" \
              "servers.load_balancer.requests.count"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Focus Firefox and navigate directly to the Graphite Dashboard interface
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take an initial screenshot proving the task began at the proper URL
take_screenshot /tmp/incident_blast_radius_visualization_start_screenshot.png

echo "=== incident_blast_radius_visualization setup complete ==="