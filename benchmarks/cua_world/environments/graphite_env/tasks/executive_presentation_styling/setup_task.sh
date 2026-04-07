#!/bin/bash
echo "=== Setting up executive_presentation_styling task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/executive_presentation_styling_result.json 2>/dev/null || true
rm -f /tmp/executive_presentation_styling_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Customer Monthly Report'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Customer Monthly Report' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Record task start timestamp
date +%s > /tmp/executive_presentation_styling_start_ts

# Navigate to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/executive_presentation_styling_start_screenshot.png

echo "=== executive_presentation_styling setup complete ==="