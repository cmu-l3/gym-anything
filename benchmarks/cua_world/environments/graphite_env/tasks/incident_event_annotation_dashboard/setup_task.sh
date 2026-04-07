#!/bin/bash
echo "=== Setting up incident_event_annotation_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/incident_event_annotation_dashboard_result.json 2>/dev/null || true
rm -f /tmp/incident_event_annotation_dashboard_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard and events to ensure clean environment
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Sev1 Mitigation Review'")
    cursor.execute("DELETE FROM events_event WHERE tags LIKE '%mitigation_applied%'")
    conn.commit()
    conn.close()
    print("Cleaned up existing target dashboard and events")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist in Carbon
for metric in "servers.rds_database.cpu.utilization" \
              "servers.load_balancer.requests.count"; do
    if metric_exists "$metric"; then
        echo "  Found required metric: $metric"
    else
        echo "  WARNING: Missing required metric: $metric"
    fi
done

# Record task start timestamp for anti-gaming (checking event creation time)
date +%s > /tmp/incident_event_annotation_dashboard_start_ts

# Navigate Firefox to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/incident_event_annotation_dashboard_start_screenshot.png

echo "=== incident_event_annotation_dashboard setup complete ==="