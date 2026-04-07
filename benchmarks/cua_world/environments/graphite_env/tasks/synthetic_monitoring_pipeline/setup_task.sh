#!/bin/bash
echo "=== Setting up synthetic_monitoring_pipeline task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Record task start time
date +%s > /tmp/synthetic_monitoring_pipeline_start_ts

# Remove stale result files
rm -f /tmp/synthetic_monitoring_pipeline_result.json 2>/dev/null || true
rm -f /tmp/synthetic_monitoring_pipeline_dashboards.json 2>/dev/null || true
rm -f /tmp/synthetic_monitoring_pipeline_metrics.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name and clean whisper files
docker exec graphite python3 - << 'PYEOF'
import sqlite3, os, shutil
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Payment Service Health'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Payment Service Health' dashboard")
except Exception as e:
    print(f"Note (Dashboard Cleanup): {e}")

try:
    whisper_dir = '/opt/graphite/storage/whisper/apps'
    if os.path.exists(whisper_dir):
        shutil.rmtree(whisper_dir)
        print("Cleaned up existing apps whisper files")
except Exception as e:
    print(f"Note (Whisper Cleanup): {e}")
PYEOF

# Rebuild index
docker exec graphite /opt/graphite/bin/build-index.sh 2>/dev/null || true

# Verify required infrastructure metric exists
echo "Checking infrastructure metric..."
if metric_exists "servers.ec2_instance_1.cpu.utilization"; then
    echo "  Found: servers.ec2_instance_1.cpu.utilization"
else
    echo "  WARNING: Missing: servers.ec2_instance_1.cpu.utilization"
fi

# Navigate to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Open terminal for agent to use
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/synthetic_monitoring_pipeline_start_screenshot.png 2>/dev/null || true

echo "=== synthetic_monitoring_pipeline setup complete ==="