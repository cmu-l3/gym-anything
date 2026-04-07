#!/bin/bash
echo "=== Setting up cdn_performance_divergence_analysis task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/cdn_performance_divergence_analysis_result.json 2>/dev/null || true
rm -f /tmp/cdn_performance_divergence_analysis_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'CDN Routing Divergence'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'CDN Routing Divergence' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist
echo "Checking for required traffic speed metrics..."
for metric in "servers.web_traffic.speed_sensor_1" \
              "servers.web_traffic.speed_sensor_2"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric (Collectd/NAB might still be populating)"
    fi
done

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/cdn_performance_divergence_analysis_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot showing clean dashboard state
take_screenshot /tmp/cdn_performance_divergence_analysis_start_screenshot.png

echo "=== cdn_performance_divergence_analysis setup complete ==="