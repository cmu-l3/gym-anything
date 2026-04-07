#!/bin/bash
echo "=== Setting up whisper_namespace_migration task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/whisper_namespace_migration_result.json 2>/dev/null || true
rm -f /tmp/whisper_export.py 2>/dev/null || true

# Delete any pre-existing dashboard with the target name to ensure a clean slate
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Namespace Migration Audit'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Namespace Migration Audit' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify that the legacy metrics exist in the servers namespace
echo "Checking legacy metric paths..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.load_balancer.requests.count"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/whisper_namespace_migration_start_ts

# Navigate Firefox to the Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot of the starting state
take_screenshot /tmp/whisper_namespace_migration_start_screenshot.png

echo "=== whisper_namespace_migration setup complete ==="