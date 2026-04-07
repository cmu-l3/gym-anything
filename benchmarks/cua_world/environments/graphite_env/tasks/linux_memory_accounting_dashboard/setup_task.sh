#!/bin/bash
echo "=== Setting up linux_memory_accounting_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/linux_memory_accounting_dashboard_result.json 2>/dev/null || true
rm -f /tmp/linux_memory_accounting_dashboard_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Linux Memory Accounting'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Linux Memory Accounting' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required collectd metrics exist
echo "Checking for required collectd memory metrics..."
if metric_exists "collectd.*.memory.*"; then
    echo "  Found: collectd memory metrics"
else
    echo "  WARNING: collectd memory metrics not yet visible. They may take a few moments to appear."
fi

# Record task start timestamp (anti-gaming)
date +%s > /tmp/linux_memory_accounting_dashboard_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/linux_memory_accounting_dashboard_start_screenshot.png

echo "=== linux_memory_accounting_dashboard setup complete ==="