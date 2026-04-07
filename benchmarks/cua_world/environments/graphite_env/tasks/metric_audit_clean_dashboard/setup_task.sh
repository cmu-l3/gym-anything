#!/bin/bash
echo "=== Setting up metric_audit_clean_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/metric_audit_clean_dashboard_result.json 2>/dev/null || true
rm -f /tmp/metric_audit_clean_dashboard_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Validated Production Metrics'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Validated Production Metrics' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# === CONTAMINATION INJECTION ===
# Feed fake/invalid metrics into Carbon to pollute the metric tree.
# These will appear in the Graphite metric browser alongside real metrics.
echo "Injecting contamination metrics into Carbon..."

python3 - << 'PYEOF'
import socket
import time

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('localhost', 2003))

now = int(time.time())

# Send 12 data points per fake metric (last hour at 5-min intervals)
# This ensures the metrics are fully indexed and visible in the metric tree
contamination = [
    'servers.UNKNOWN_HOST.cpu.utilization',
    'servers.ec2_instance_99.cpu.utilization',
    'servers.test_node.machine_temperature',
]

for i in range(12):
    ts = now - (11 - i) * 300
    values = [55.0 + i * 0.4, 72.0 + i * 0.3, 38.0 + i * 0.1]
    for metric, val in zip(contamination, values):
        msg = f"{metric} {val:.2f} {ts}\n"
        s.sendall(msg.encode())

s.close()
print("Contamination metrics injected successfully")
PYEOF

# Wait for Carbon to process and index the new metrics
echo "Waiting for Carbon to index contamination metrics..."
sleep 10

# Verify contamination metrics are now visible
echo "Verifying contamination metrics exist..."
for metric in "servers.UNKNOWN_HOST.cpu.utilization" \
              "servers.ec2_instance_99.cpu.utilization" \
              "servers.test_node.machine_temperature"; do
    if metric_exists "$metric"; then
        echo "  Contamination seeded: $metric"
    else
        echo "  WARNING: Contamination metric not yet indexed: $metric"
    fi
done

# Verify legitimate metrics also exist
echo "Verifying legitimate metrics exist..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.ec2_instance_2.cpu.utilization" \
              "servers.ec2_instance_3.cpu.cloudwatch_utilization"; do
    if metric_exists "$metric"; then
        echo "  Legitimate metric found: $metric"
    else
        echo "  WARNING: Missing legitimate metric: $metric"
    fi
done

# Record task start timestamp (after contamination injection)
date +%s > /tmp/metric_audit_clean_dashboard_start_ts

# Navigate to Graphite metric browser so agent can see the contaminated tree
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot showing the contaminated environment
take_screenshot /tmp/metric_audit_clean_dashboard_start_screenshot.png

echo "=== metric_audit_clean_dashboard setup complete ==="
echo "Contamination injected. Agent must identify and exclude:"
echo "  - servers.UNKNOWN_HOST.cpu.utilization"
echo "  - servers.ec2_instance_99.cpu.utilization"
echo "  - servers.test_node.machine_temperature"
