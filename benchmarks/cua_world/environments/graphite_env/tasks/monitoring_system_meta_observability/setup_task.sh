#!/bin/bash
echo "=== Setting up monitoring_system_meta_observability task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready and collecting data
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/monitoring_system_meta_observability_result.json 2>/dev/null || true
rm -f /tmp/monitoring_system_meta_observability_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Graphite Health'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Graphite Health' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify internal metrics exist
echo "Checking for required internal and OS metrics..."
for metric in "carbon.agents" "collectd"; do
    if metric_exists "$metric"; then
        echo "  Found namespace: $metric"
    else
        echo "  WARNING: Missing namespace: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/monitoring_system_meta_observability_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/monitoring_system_meta_observability_start_screenshot.png

echo "=== monitoring_system_meta_observability setup complete ==="